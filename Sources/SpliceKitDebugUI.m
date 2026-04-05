//
//  SpliceKitDebugUI.m
//  Rebuilds FCP's hidden Debug preferences pane + Debug menu bar programmatically.
//
//  The Debug preferences module (PEAppDebugPreferencesModule) is still compiled
//  into FCP, but Apple strips PEAppDebugPreferencesModule.nib from the bundle
//  during release builds. At runtime LKPreferences calls addPreferenceNamed:owner:
//  which tries to load the NIB via preferencesNibName and silently drops the
//  module when it fails.
//
//  We work around the silent filter by:
//    1. Building the view in code (no NIB needed).
//    2. Calling setPreferencesView: on the module so it owns our view.
//    3. Mutating LKPreferences' internal arrays/dictionary directly to add the
//       Debug pane to _preferenceTitles, _preferenceModules, and
//       _masterPreferenceViews.
//    4. Calling _setupToolbar so the Settings-window toolbar picks up the new
//       tab without a relaunch.
//
//  The Debug menu bar is simpler: build an NSMenu tree, wire each item's
//  target/action to our controller, and insert the top-level item before Help.
//

#import "SpliceKitDebugUI.h"
#import "SpliceKit.h"
#import <AppKit/AppKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

#pragma mark - Shared Helpers

// Some NSUserDefaults keys we need to read from the same helper set that
// SpliceKitServer already curates. Duplicating a tiny subset here keeps this
// file standalone rather than pulling in the server's header surface.
static NSArray<NSString *> *SKDebug_tlkVisualFlags(void) {
    return @[
        @"TLKShowItemLaneIndex",
        @"TLKShowMisalignedEdges",
        @"TLKShowRenderBar",
        @"TLKShowHiddenGapItems",
        @"TLKShowHiddenItemHeaders",
        @"TLKShowInvalidLayoutRects",
        @"TLKShowContainerBounds",
        @"TLKShowContentLayers",
        @"TLKShowRulerBounds",
        @"TLKShowUsedRegion",
        @"TLKShowZeroHeightSpineItems",
        @"TLKDebugColorChangedObjects",
    ];
}

static NSArray<NSString *> *SKDebug_tlkLoggingFlags(void) {
    return @[
        @"TLKLogVisibleLayerChanges",
        @"TLKLogParts",
        @"TLKLogReloadRequests",
        @"TLKLogRecyclingLayerChanges",
        @"TLKLogVisibleRectChanges",
        @"TLKLogSegmentationStatistics",
    ];
}

static NSArray<NSString *> *SKDebug_renderFlags(void) {
    return @[
        @"TLKPerformanceMonitorEnabled",
        @"TLKDisableItemContents",
        @"DebugKeyItemVideoFilmstripsDisabled",
        @"DebugKeyItemBackgroundDisabled",
        @"DebugKeyItemAudioWaveformsDisabled",
        @"GPU_LOGGING",
    ];
}

static NSArray<NSString *> *SKDebug_fcpBehaviorFlags(void) {
    return @[
        @"FFDontCoalesceGaps",
        @"FFDisableSnapping",
        @"FFDisableSkimming",
    ];
}

static NSArray<NSString *> *SKDebug_logLevelNames(void) {
    return @[@"trace", @"debug", @"info", @"warning", @"error", @"failure"];
}

static NSString *SKDebug_humanizeKey(NSString *key) {
    // TLKShowHiddenGapItems -> "Show Hidden Gap Items"
    if ([key hasPrefix:@"TLK"]) key = [key substringFromIndex:3];
    if ([key hasPrefix:@"DebugKey"]) key = [key substringFromIndex:8];
    if ([key hasPrefix:@"FF"]) key = [key substringFromIndex:2];
    NSMutableString *out = [NSMutableString string];
    for (NSUInteger i = 0; i < key.length; i++) {
        unichar c = [key characterAtIndex:i];
        if (i > 0 && c >= 'A' && c <= 'Z') {
            unichar prev = [key characterAtIndex:i - 1];
            if (prev >= 'a' && prev <= 'z') [out appendString:@" "];
        }
        [out appendFormat:@"%C", c];
    }
    return out;
}

// Sender-agnostic key lookup. NSView subclasses (NSButton, NSPopUpButton) use
// `identifier`; NSMenuItem uses `representedObject`. This returns whichever
// is set so action methods can be shared between views and menu items.
static NSString *SKDebug_senderKey(id sender) {
    if ([sender isKindOfClass:[NSMenuItem class]]) {
        id obj = [(NSMenuItem *)sender representedObject];
        if ([obj isKindOfClass:[NSString class]]) return obj;
    }
    if ([sender isKindOfClass:[NSView class]]) {
        return [(NSView *)sender identifier];
    }
    return nil;
}

// After we change flags, reload FCP's TLK cache so they take effect live.
static void SKDebug_reloadTLKIfPossible(void) {
    Class tlkClass = NSClassFromString(@"TLKUserDefaults");
    if (tlkClass) {
        SEL sel = NSSelectorFromString(@"_loadUserDefaults");
        if ([tlkClass respondsToSelector:sel]) {
            ((void (*)(id, SEL))objc_msgSend)(tlkClass, sel);
        }
    }
}

#pragma mark - Controller (owns targets for all actions)

@interface SpliceKitDebugController : NSObject <NSMenuDelegate>
+ (instancetype)shared;
@property (nonatomic, weak) NSMenuItem *debugMenuItem;  // the top-level bar item
@property (nonatomic, weak) id debugPrefsModule;        // PEAppDebugPreferencesModule instance
@property (nonatomic, strong) NSView *debugPrefsView;   // our programmatic view
@end

@implementation SpliceKitDebugController

+ (instancetype)shared {
    static SpliceKitDebugController *instance = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ instance = [[self alloc] init]; });
    return instance;
}

#pragma mark Checkbox actions

- (void)toggleBoolDefault:(id)sender {
    if (![sender isKindOfClass:[NSButton class]] && ![sender isKindOfClass:[NSMenuItem class]]) return;
    NSString *key = SKDebug_senderKey(sender);
    if (key.length == 0) return;

    BOOL current = [[NSUserDefaults standardUserDefaults] boolForKey:key];
    BOOL newValue = !current;
    [[NSUserDefaults standardUserDefaults] setBool:newValue forKey:key];
    [[NSUserDefaults standardUserDefaults] synchronize];

    if ([sender isKindOfClass:[NSButton class]]) {
        [(NSButton *)sender setState:newValue ? NSControlStateValueOn : NSControlStateValueOff];
    } else {
        [(NSMenuItem *)sender setState:newValue ? NSControlStateValueOn : NSControlStateValueOff];
    }

    SKDebug_reloadTLKIfPossible();
    SpliceKit_log(@"Debug flag %@ -> %@", key, newValue ? @"YES" : @"NO");
}

- (void)setLogLevel:(id)sender {
    NSInteger level = -1;
    if ([sender isKindOfClass:[NSPopUpButton class]]) {
        level = [(NSPopUpButton *)sender indexOfSelectedItem];
    } else if ([sender isKindOfClass:[NSMenuItem class]]) {
        level = [(NSMenuItem *)sender tag];
    }
    if (level < 0 || level >= (NSInteger)SKDebug_logLevelNames().count) return;
    [[NSUserDefaults standardUserDefaults] setInteger:level forKey:@"LogLevel"];
    [[NSUserDefaults standardUserDefaults] synchronize];
    SpliceKit_log(@"ProAppSupport LogLevel -> %@", SKDebug_logLevelNames()[level]);
}

- (void)setIntDefault:(id)sender {
    // Used by CFPreferences integer popups (VideoDecoderLogLevelInNLE, FrameDropLogLevel).
    // The view's identifier stores the CFPreferences key; the popup's selected
    // index is the integer value (since items are titled 0..5).
    if (![sender isKindOfClass:[NSPopUpButton class]]) return;
    NSPopUpButton *popup = sender;
    NSString *key = SKDebug_senderKey(popup);
    if (key.length == 0) return;
    NSInteger value = popup.indexOfSelectedItem;
    CFPreferencesSetAppValue((__bridge CFStringRef)key,
                             (__bridge CFPropertyListRef)@(value),
                             kCFPreferencesCurrentApplication);
    CFPreferencesAppSynchronize(kCFPreferencesCurrentApplication);
    SpliceKit_log(@"CFPreferences %@ -> %ld", key, (long)value);
}

#pragma mark Preset actions

- (void)applyPreset:(id)sender {
    NSString *preset = SKDebug_senderKey(sender);
    if (preset.length == 0) return;

    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    void (^set)(NSString *, BOOL) = ^(NSString *key, BOOL val) {
        [d setBool:val forKey:key];
    };

    if ([preset isEqualToString:@"timeline_visual"]) {
        set(@"TLKShowItemLaneIndex", YES);
        set(@"TLKShowMisalignedEdges", YES);
        set(@"TLKShowRenderBar", YES);
        set(@"TLKShowHiddenGapItems", YES);
        set(@"TLKShowInvalidLayoutRects", YES);
        set(@"TLKDebugColorChangedObjects", YES);
    } else if ([preset isEqualToString:@"timeline_logging"]) {
        for (NSString *k in SKDebug_tlkLoggingFlags()) set(k, YES);
    } else if ([preset isEqualToString:@"performance"]) {
        set(@"TLKPerformanceMonitorEnabled", YES);
        [d setInteger:2 forKey:@"VideoDecoderLogLevelInNLE"];
        [d setInteger:2 forKey:@"FrameDropLogLevel"];
    } else if ([preset isEqualToString:@"render_debug"]) {
        set(@"DebugKeyItemVideoFilmstripsDisabled", YES);
        set(@"DebugKeyItemBackgroundDisabled", YES);
        set(@"DebugKeyItemAudioWaveformsDisabled", YES);
        set(@"TLKDisableItemContents", YES);
        set(@"GPU_LOGGING", YES);
    } else if ([preset isEqualToString:@"verbose_logging"]) {
        [d setInteger:0 forKey:@"LogLevel"];
        set(@"LogUI", YES);
        set(@"LogThread", YES);
        set(@"EnableScheduledReadAudioLogging", YES);
    } else if ([preset isEqualToString:@"all_off"]) {
        for (NSString *k in SKDebug_tlkVisualFlags()) [d removeObjectForKey:k];
        for (NSString *k in SKDebug_tlkLoggingFlags()) [d removeObjectForKey:k];
        for (NSString *k in SKDebug_renderFlags()) [d removeObjectForKey:k];
        for (NSString *k in SKDebug_fcpBehaviorFlags()) [d removeObjectForKey:k];
        [d removeObjectForKey:@"LogLevel"];
        [d removeObjectForKey:@"LogUI"];
        [d removeObjectForKey:@"LogThread"];
        [d removeObjectForKey:@"LogCategory"];
        [d removeObjectForKey:@"EnableScheduledReadAudioLogging"];
        // Clear integer CFPreferences keys set by the performance preset
        [d removeObjectForKey:@"VideoDecoderLogLevelInNLE"];
        [d removeObjectForKey:@"FrameDropLogLevel"];
    }

    [d synchronize];
    SKDebug_reloadTLKIfPossible();
    SpliceKit_log(@"Applied debug preset: %@", preset);
}

#pragma mark FCP-native debug actions

- (void)toggleCGContextDraw:(id)sender {
    // -[PEAppController toggleDebugCGContextDraw:] — single documented debug
    // action exposed by the app controller. Find the shared instance and ping it.
    Class appCtlClass = objc_getClass("PEAppController");
    if (!appCtlClass) return;
    id appCtl = nil;
    if ([appCtlClass respondsToSelector:@selector(sharedAppController)]) {
        appCtl = ((id (*)(id, SEL))objc_msgSend)(appCtlClass, @selector(sharedAppController));
    }
    if (!appCtl) {
        appCtl = [NSApp delegate];
    }
    SEL sel = NSSelectorFromString(@"toggleDebugCGContextDraw:");
    if ([appCtl respondsToSelector:sel]) {
        ((void (*)(id, SEL, id))objc_msgSend)(appCtl, sel, sender);
        SpliceKit_log(@"Invoked PEAppController.toggleDebugCGContextDraw:");
    } else {
        SpliceKit_log(@"PEAppController does not respond to toggleDebugCGContextDraw:");
    }
}

- (void)toggleSaveSearchResults:(id)sender {
    Class vamlClass = objc_getClass("FFVAMLDebugMenu");
    if (!vamlClass) return;
    id vaml = ((id (*)(id, SEL))objc_msgSend)(vamlClass, @selector(instance));
    SEL sel = NSSelectorFromString(@"toggleSaveSearchResults");
    if ([vaml respondsToSelector:sel]) {
        ((void (*)(id, SEL))objc_msgSend)(vaml, sel);
    }
}

- (void)toggleSaveTranscription:(id)sender {
    Class vamlClass = objc_getClass("FFVAMLDebugMenu");
    if (!vamlClass) return;
    id vaml = ((id (*)(id, SEL))objc_msgSend)(vamlClass, @selector(instance));
    SEL sel = NSSelectorFromString(@"toggleSaveTranscription");
    if ([vaml respondsToSelector:sel]) {
        ((void (*)(id, SEL))objc_msgSend)(vaml, sel);
    }
}

#pragma mark Framerate monitor

- (void)startFramerateMonitor:(id)sender {
    Class hmd = NSClassFromString(@"HMDFramerate");
    if (!hmd) {
        SpliceKit_log(@"HMDFramerate class not found");
        return;
    }
    id monitor = [[hmd alloc] init];
    SEL startSel = NSSelectorFromString(@"startLogging:");
    if ([monitor respondsToSelector:startSel]) {
        ((void (*)(id, SEL, float))objc_msgSend)(monitor, startSel, 2.0f);
        // Retain the monitor in an associated object so it's not deallocated.
        objc_setAssociatedObject(self, "skFramerateMonitor", monitor,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        SpliceKit_log(@"Framerate monitor started (2.0s interval)");
    }
}

- (void)stopFramerateMonitor:(id)sender {
    id monitor = objc_getAssociatedObject(self, "skFramerateMonitor");
    if (!monitor) return;
    SEL stopSel = NSSelectorFromString(@"stopLogging");
    if ([monitor respondsToSelector:stopSel]) {
        ((void (*)(id, SEL))objc_msgSend)(monitor, stopSel);
    }
    objc_setAssociatedObject(self, "skFramerateMonitor", nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    SpliceKit_log(@"Framerate monitor stopped");
}

#pragma mark User defaults reset (from the module's own clearUserDefaults:)

- (void)clearAllDebugFlags:(id)sender {
    // Uses the module's own clearUserDefaults: if we have a handle to it;
    // otherwise falls through to our own per-key clear.
    id module = self.debugPrefsModule;
    SEL sel = NSSelectorFromString(@"clearUserDefaults:");
    if (module && [module respondsToSelector:sel]) {
        ((void (*)(id, SEL, id))objc_msgSend)(module, sel, sender);
        return;
    }
    [self applyPreset:nil];  // no-op if representedObject nil
    // Direct clear as fallback
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    for (NSString *k in SKDebug_tlkVisualFlags()) [d removeObjectForKey:k];
    for (NSString *k in SKDebug_tlkLoggingFlags()) [d removeObjectForKey:k];
    for (NSString *k in SKDebug_renderFlags()) [d removeObjectForKey:k];
    for (NSString *k in SKDebug_fcpBehaviorFlags()) [d removeObjectForKey:k];
    [d synchronize];
    SKDebug_reloadTLKIfPossible();
}

#pragma mark NSMenuDelegate — sync checkbox state with NSUserDefaults

- (void)menuNeedsUpdate:(NSMenu *)menu {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    for (NSMenuItem *item in menu.itemArray) {
        NSString *key = [item representedObject];
        if ([key isKindOfClass:[NSString class]] && [key length] > 0 && item.action == @selector(toggleBoolDefault:)) {
            BOOL on = [d boolForKey:key];
            item.state = on ? NSControlStateValueOn : NSControlStateValueOff;
        }
    }
}

@end

#pragma mark - Programmatic View Construction

// Builds a labeled checkbox row bound to a BOOL NSUserDefaults key.
static NSButton *SKDebug_makeCheckbox(NSString *key, NSString *title) {
    NSButton *cb = [NSButton checkboxWithTitle:title
                                        target:[SpliceKitDebugController shared]
                                        action:@selector(toggleBoolDefault:)];
    cb.identifier = key;  // toggleBoolDefault: reads this via SKDebug_senderKey
    cb.state = [[NSUserDefaults standardUserDefaults] boolForKey:key]
               ? NSControlStateValueOn : NSControlStateValueOff;
    cb.translatesAutoresizingMaskIntoConstraints = NO;
    return cb;
}

static NSTextField *SKDebug_makeSectionLabel(NSString *text) {
    NSTextField *label = [NSTextField labelWithString:text];
    label.font = [NSFont boldSystemFontOfSize:13];
    label.textColor = [NSColor labelColor];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    return label;
}

static NSBox *SKDebug_makeSeparator(void) {
    NSBox *box = [[NSBox alloc] initWithFrame:NSMakeRect(0, 0, 400, 1)];
    box.boxType = NSBoxSeparator;
    box.translatesAutoresizingMaskIntoConstraints = NO;
    return box;
}

static NSStackView *SKDebug_makeCheckboxGroup(NSArray<NSString *> *keys) {
    NSStackView *stack = [NSStackView stackViewWithViews:@[]];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 4;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    for (NSString *key in keys) {
        [stack addArrangedSubview:SKDebug_makeCheckbox(key, SKDebug_humanizeKey(key))];
    }
    return stack;
}

static NSButton *SKDebug_makePresetButton(NSString *title, NSString *preset) {
    NSButton *btn = [NSButton buttonWithTitle:title
                                       target:[SpliceKitDebugController shared]
                                       action:@selector(applyPreset:)];
    btn.identifier = preset;  // applyPreset: reads this via SKDebug_senderKey
    btn.bezelStyle = NSBezelStyleRounded;
    btn.translatesAutoresizingMaskIntoConstraints = NO;
    return btn;
}

// Build the entire Debug preferences content view. Returned view has a fixed
// intrinsic size so LKPreferences can size its window around it.
static NSView *SKDebug_buildDebugPrefsView(void) {
    const CGFloat kWidth = 560.0;

    // The root doc view for a scroll view — it grows vertically as we add sections.
    NSView *doc = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, kWidth, 1200)];
    doc.translatesAutoresizingMaskIntoConstraints = NO;

    NSStackView *root = [NSStackView stackViewWithViews:@[]];
    root.orientation = NSUserInterfaceLayoutOrientationVertical;
    root.alignment = NSLayoutAttributeLeading;
    root.spacing = 10;
    root.edgeInsets = NSEdgeInsetsMake(16, 20, 16, 20);
    root.translatesAutoresizingMaskIntoConstraints = NO;
    [doc addSubview:root];
    [NSLayoutConstraint activateConstraints:@[
        [root.topAnchor constraintEqualToAnchor:doc.topAnchor],
        [root.leadingAnchor constraintEqualToAnchor:doc.leadingAnchor],
        [root.trailingAnchor constraintEqualToAnchor:doc.trailingAnchor],
        [root.bottomAnchor constraintEqualToAnchor:doc.bottomAnchor],
    ]];

    // Header
    NSTextField *header = [NSTextField labelWithString:
        @"Debug — Reconstructed by SpliceKit. Flags mirror Final Cut Pro's "
        @"internal developer defaults (TLKUserDefaults, CFPreferences, "
        @"ProAppSupport log)."];
    header.font = [NSFont systemFontOfSize:11];
    header.textColor = [NSColor secondaryLabelColor];
    header.maximumNumberOfLines = 0;
    header.preferredMaxLayoutWidth = kWidth - 40;
    header.translatesAutoresizingMaskIntoConstraints = NO;
    [root addArrangedSubview:header];
    [root addArrangedSubview:SKDebug_makeSeparator()];

    // --- Timeline Visual Overlays ---
    [root addArrangedSubview:SKDebug_makeSectionLabel(@"Timeline Visual Overlays")];
    [root addArrangedSubview:SKDebug_makeCheckboxGroup(SKDebug_tlkVisualFlags())];
    [root addArrangedSubview:SKDebug_makeSeparator()];

    // --- Timeline Logging ---
    [root addArrangedSubview:SKDebug_makeSectionLabel(@"Timeline Logging")];
    [root addArrangedSubview:SKDebug_makeCheckboxGroup(SKDebug_tlkLoggingFlags())];
    [root addArrangedSubview:SKDebug_makeSeparator()];

    // --- Performance & Rendering ---
    [root addArrangedSubview:SKDebug_makeSectionLabel(@"Performance & Rendering")];
    [root addArrangedSubview:SKDebug_makeCheckboxGroup(SKDebug_renderFlags())];
    [root addArrangedSubview:SKDebug_makeSeparator()];

    // --- FCP Behavior Overrides ---
    [root addArrangedSubview:SKDebug_makeSectionLabel(@"FCP Behavior Overrides")];
    [root addArrangedSubview:SKDebug_makeCheckboxGroup(SKDebug_fcpBehaviorFlags())];
    [root addArrangedSubview:SKDebug_makeSeparator()];

    // --- ProAppSupport Log ---
    [root addArrangedSubview:SKDebug_makeSectionLabel(@"ProAppSupport Log")];
    {
        NSStackView *row = [NSStackView stackViewWithViews:@[]];
        row.orientation = NSUserInterfaceLayoutOrientationHorizontal;
        row.alignment = NSLayoutAttributeCenterY;
        row.spacing = 8;
        row.translatesAutoresizingMaskIntoConstraints = NO;

        NSTextField *logLevelLabel = [NSTextField labelWithString:@"Log Level:"];
        [row addArrangedSubview:logLevelLabel];

        NSPopUpButton *levelPopup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
        for (NSString *name in SKDebug_logLevelNames()) {
            [levelPopup addItemWithTitle:[name capitalizedString]];
        }
        NSInteger currentLevel = [[NSUserDefaults standardUserDefaults] integerForKey:@"LogLevel"];
        if (currentLevel < 0 || currentLevel >= (NSInteger)SKDebug_logLevelNames().count) currentLevel = 2;
        [levelPopup selectItemAtIndex:currentLevel];
        levelPopup.target = [SpliceKitDebugController shared];
        levelPopup.action = @selector(setLogLevel:);
        [row addArrangedSubview:levelPopup];
        [row addArrangedSubview:SKDebug_makeCheckbox(@"LogUI", @"Show In-App Log Panel")];
        [row addArrangedSubview:SKDebug_makeCheckbox(@"LogThread", @"Include Thread Info")];
        [root addArrangedSubview:row];
    }

    // --- CFPreferences integer popups ---
    {
        NSStackView *row = [NSStackView stackViewWithViews:@[]];
        row.orientation = NSUserInterfaceLayoutOrientationHorizontal;
        row.alignment = NSLayoutAttributeCenterY;
        row.spacing = 8;

        NSTextField *label1 = [NSTextField labelWithString:@"Video Decoder Log:"];
        [row addArrangedSubview:label1];
        NSPopUpButton *p1 = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
        for (int i = 0; i <= 5; i++) [p1 addItemWithTitle:[@(i) stringValue]];
        {
            CFPropertyListRef raw = CFPreferencesCopyAppValue(CFSTR("VideoDecoderLogLevelInNLE"),
                                                              kCFPreferencesCurrentApplication);
            NSInteger idx = raw ? [(__bridge_transfer NSNumber *)raw integerValue] : 0;
            if (idx < 0 || idx > 5) idx = 0;
            [p1 selectItemAtIndex:idx];
        }
        p1.identifier = @"VideoDecoderLogLevelInNLE";
        p1.target = [SpliceKitDebugController shared];
        p1.action = @selector(setIntDefault:);
        [row addArrangedSubview:p1];

        NSTextField *label2 = [NSTextField labelWithString:@"Frame Drop Log:"];
        [row addArrangedSubview:label2];
        NSPopUpButton *p2 = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
        for (int i = 0; i <= 5; i++) [p2 addItemWithTitle:[@(i) stringValue]];
        {
            CFPropertyListRef raw = CFPreferencesCopyAppValue(CFSTR("FrameDropLogLevel"),
                                                              kCFPreferencesCurrentApplication);
            NSInteger idx = raw ? [(__bridge_transfer NSNumber *)raw integerValue] : 0;
            if (idx < 0 || idx > 5) idx = 0;
            [p2 selectItemAtIndex:idx];
        }
        p2.identifier = @"FrameDropLogLevel";
        p2.target = [SpliceKitDebugController shared];
        p2.action = @selector(setIntDefault:);
        [row addArrangedSubview:p2];

        [root addArrangedSubview:row];
    }
    [root addArrangedSubview:SKDebug_makeSeparator()];

    // --- Presets (row of buttons) ---
    [root addArrangedSubview:SKDebug_makeSectionLabel(@"Presets")];
    {
        NSStackView *row1 = [NSStackView stackViewWithViews:@[
            SKDebug_makePresetButton(@"Timeline Visual", @"timeline_visual"),
            SKDebug_makePresetButton(@"Timeline Logging", @"timeline_logging"),
            SKDebug_makePresetButton(@"Performance", @"performance"),
        ]];
        row1.orientation = NSUserInterfaceLayoutOrientationHorizontal;
        row1.spacing = 8;
        [root addArrangedSubview:row1];

        NSStackView *row2 = [NSStackView stackViewWithViews:@[
            SKDebug_makePresetButton(@"Render Debug", @"render_debug"),
            SKDebug_makePresetButton(@"Verbose Logging", @"verbose_logging"),
            SKDebug_makePresetButton(@"All Off", @"all_off"),
        ]];
        row2.orientation = NSUserInterfaceLayoutOrientationHorizontal;
        row2.spacing = 8;
        [root addArrangedSubview:row2];
    }
    [root addArrangedSubview:SKDebug_makeSeparator()];

    // --- Actions ---
    [root addArrangedSubview:SKDebug_makeSectionLabel(@"Actions")];
    {
        NSStackView *row = [NSStackView stackViewWithViews:@[]];
        row.orientation = NSUserInterfaceLayoutOrientationHorizontal;
        row.spacing = 8;

        NSButton *fpsStart = [NSButton buttonWithTitle:@"Start Framerate Monitor"
                                                target:[SpliceKitDebugController shared]
                                                action:@selector(startFramerateMonitor:)];
        [row addArrangedSubview:fpsStart];

        NSButton *fpsStop = [NSButton buttonWithTitle:@"Stop Framerate Monitor"
                                               target:[SpliceKitDebugController shared]
                                               action:@selector(stopFramerateMonitor:)];
        [row addArrangedSubview:fpsStop];

        NSButton *clearBtn = [NSButton buttonWithTitle:@"Clear User Defaults…"
                                                target:[SpliceKitDebugController shared]
                                                action:@selector(clearAllDebugFlags:)];
        [row addArrangedSubview:clearBtn];

        [root addArrangedSubview:row];
    }

    return doc;
}

// Wrap the programmatic doc view in a scroll view so the panel stays usable
// even if the content grows taller than the screen.
static NSView *SKDebug_buildScrollableDebugView(void) {
    NSView *content = SKDebug_buildDebugPrefsView();

    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 600, 520)];
    scroll.hasVerticalScroller = YES;
    scroll.hasHorizontalScroller = NO;
    scroll.autohidesScrollers = YES;
    scroll.borderType = NSNoBorder;
    scroll.drawsBackground = NO;

    // The scroll view's documentView is what it scrolls inside its bounds.
    // content's intrinsicContentSize comes from the stack view's constraints,
    // so we let Auto Layout drive its height.
    content.translatesAutoresizingMaskIntoConstraints = NO;
    scroll.documentView = content;

    [NSLayoutConstraint activateConstraints:@[
        [content.topAnchor constraintEqualToAnchor:scroll.contentView.topAnchor],
        [content.leadingAnchor constraintEqualToAnchor:scroll.contentView.leadingAnchor],
        [content.trailingAnchor constraintEqualToAnchor:scroll.contentView.trailingAnchor],
        [content.widthAnchor constraintEqualToAnchor:scroll.contentView.widthAnchor],
    ]];

    return scroll;
}

#pragma mark - Preferences Panel Installation

// Reads an ivar by name using runtime APIs instead of KVC, since LKPreferences'
// ivars are underscored and KVC-illegal.
static id SKDebug_getIvar(id obj, const char *name) {
    if (!obj) return nil;
    Ivar iv = class_getInstanceVariable(object_getClass(obj), name);
    if (!iv) return nil;
    return object_getIvar(obj, iv);
}

static BOOL sDebugPrefsInstalled = NO;

BOOL SpliceKit_installDebugSettingsPanel(void) {
    if (sDebugPrefsInstalled) return YES;

    __block BOOL success = NO;

    dispatch_block_t work = ^{
        Class moduleClass = objc_getClass("PEAppDebugPreferencesModule");
        if (!moduleClass) {
            SpliceKit_log(@"PEAppDebugPreferencesModule class not found — cannot install Debug panel");
            return;
        }

        Class prefsClass = objc_getClass("LKPreferences");
        if (!prefsClass) {
            SpliceKit_log(@"LKPreferences class not found");
            return;
        }

        id shared = ((id (*)(id, SEL))objc_msgSend)((id)prefsClass, @selector(sharedPreferences));
        if (!shared) {
            SpliceKit_log(@"LKPreferences sharedPreferences returned nil");
            return;
        }

        // Instantiate the module
        id module = ((id (*)(id, SEL))objc_msgSend)((id)moduleClass, @selector(alloc));
        module = ((id (*)(id, SEL))objc_msgSend)(module, @selector(init));
        if (!module) {
            SpliceKit_log(@"Failed to init PEAppDebugPreferencesModule");
            return;
        }
        [SpliceKitDebugController shared].debugPrefsModule = module;

        // Build our programmatic view
        NSView *view = SKDebug_buildScrollableDebugView();
        [SpliceKitDebugController shared].debugPrefsView = view;

        // Hand the view to the module (so it behaves like a normal NIB-owned module)
        SEL setViewSel = @selector(setPreferencesView:);
        if ([module respondsToSelector:setViewSel]) {
            ((void (*)(id, SEL, id))objc_msgSend)(module, setViewSel, view);
        }

        // Direct mutation of LKPreferences state — bypasses the silent NIB filter.
        NSMutableArray *titles  = SKDebug_getIvar(shared, "_preferenceTitles");
        NSMutableArray *modules = SKDebug_getIvar(shared, "_preferenceModules");
        NSMutableDictionary *master = SKDebug_getIvar(shared, "_masterPreferenceViews");

        if (![titles isKindOfClass:[NSMutableArray class]] ||
            ![modules isKindOfClass:[NSMutableArray class]] ||
            ![master isKindOfClass:[NSMutableDictionary class]]) {
            SpliceKit_log(@"LKPreferences ivars have unexpected types — aborting install");
            return;
        }

        NSString *title = @"Debug";

        if ([titles containsObject:title]) {
            SpliceKit_log(@"Debug pane already registered");
            sDebugPrefsInstalled = YES;
            success = YES;
            return;
        }

        [titles addObject:title];
        [modules addObject:module];
        master[title] = view;

        // Rebuild the toolbar so the Debug tab appears. Private but stable — it's
        // the same method LKPreferences calls from addPreferenceNamed:owner:.
        SEL setupToolbar = NSSelectorFromString(@"_setupToolbar");
        if ([shared respondsToSelector:setupToolbar]) {
            ((void (*)(id, SEL))objc_msgSend)(shared, setupToolbar);
        }

        // Also update the panel's size constraint if it's open
        SEL updateFrame = @selector(updatePanelFrameAnimated:);
        if ([shared respondsToSelector:updateFrame]) {
            ((void (*)(id, SEL, BOOL))objc_msgSend)(shared, updateFrame, NO);
        }

        sDebugPrefsInstalled = YES;
        success = YES;
        SpliceKit_log(@"Debug preferences pane installed");
    };

    if ([NSThread isMainThread]) {
        work();
    } else {
        dispatch_sync(dispatch_get_main_queue(), work);
    }

    return success;
}

BOOL SpliceKit_uninstallDebugSettingsPanel(void) {
    if (!sDebugPrefsInstalled) return YES;

    __block BOOL success = NO;
    dispatch_block_t work = ^{
        Class prefsClass = objc_getClass("LKPreferences");
        if (!prefsClass) return;
        id shared = ((id (*)(id, SEL))objc_msgSend)((id)prefsClass, @selector(sharedPreferences));
        if (!shared) return;

        NSMutableArray *titles  = SKDebug_getIvar(shared, "_preferenceTitles");
        NSMutableArray *modules = SKDebug_getIvar(shared, "_preferenceModules");
        NSMutableDictionary *master = SKDebug_getIvar(shared, "_masterPreferenceViews");

        NSUInteger idx = [titles indexOfObject:@"Debug"];
        if (idx != NSNotFound) {
            [titles removeObjectAtIndex:idx];
            if (idx < modules.count) [modules removeObjectAtIndex:idx];
            [master removeObjectForKey:@"Debug"];
        }

        SEL setupToolbar = NSSelectorFromString(@"_setupToolbar");
        if ([shared respondsToSelector:setupToolbar]) {
            ((void (*)(id, SEL))objc_msgSend)(shared, setupToolbar);
        }

        [SpliceKitDebugController shared].debugPrefsModule = nil;
        [SpliceKitDebugController shared].debugPrefsView = nil;
        sDebugPrefsInstalled = NO;
        success = YES;
    };

    if ([NSThread isMainThread]) work(); else dispatch_sync(dispatch_get_main_queue(), work);
    return success;
}

BOOL SpliceKit_isDebugSettingsPanelInstalled(void) {
    return sDebugPrefsInstalled;
}

#pragma mark - Debug Menu Bar

// Build a submenu of checkbox items bound to BOOL defaults.
static NSMenu *SKDebug_buildCheckboxSubmenu(NSString *title, NSArray<NSString *> *keys) {
    NSMenu *menu = [[NSMenu alloc] initWithTitle:title];
    menu.autoenablesItems = YES;
    menu.delegate = [SpliceKitDebugController shared];
    SpliceKitDebugController *ctl = [SpliceKitDebugController shared];
    for (NSString *key in keys) {
        NSMenuItem *item = [[NSMenuItem alloc]
            initWithTitle:SKDebug_humanizeKey(key)
                   action:@selector(toggleBoolDefault:)
            keyEquivalent:@""];
        item.representedObject = key;
        item.target = ctl;
        item.state = [[NSUserDefaults standardUserDefaults] boolForKey:key]
                     ? NSControlStateValueOn : NSControlStateValueOff;
        [menu addItem:item];
    }
    return menu;
}

static NSMenuItem *SKDebug_buildDebugMenuItem(void) {
    SpliceKitDebugController *ctl = [SpliceKitDebugController shared];

    NSMenu *root = [[NSMenu alloc] initWithTitle:@"Debug"];
    root.autoenablesItems = YES;

    // Timeline Overlays submenu
    NSMenuItem *overlays = [[NSMenuItem alloc] initWithTitle:@"Timeline Overlays"
                                                      action:nil keyEquivalent:@""];
    overlays.submenu = SKDebug_buildCheckboxSubmenu(@"Timeline Overlays", SKDebug_tlkVisualFlags());
    [root addItem:overlays];

    // Timeline Logging submenu
    NSMenuItem *logging = [[NSMenuItem alloc] initWithTitle:@"Timeline Logging"
                                                     action:nil keyEquivalent:@""];
    logging.submenu = SKDebug_buildCheckboxSubmenu(@"Timeline Logging", SKDebug_tlkLoggingFlags());
    [root addItem:logging];

    // Rendering / Performance submenu
    NSMenuItem *render = [[NSMenuItem alloc] initWithTitle:@"Rendering & Performance"
                                                    action:nil keyEquivalent:@""];
    render.submenu = SKDebug_buildCheckboxSubmenu(@"Rendering & Performance", SKDebug_renderFlags());
    [root addItem:render];

    // FCP Behavior submenu
    NSMenuItem *fcp = [[NSMenuItem alloc] initWithTitle:@"FCP Behavior"
                                                 action:nil keyEquivalent:@""];
    fcp.submenu = SKDebug_buildCheckboxSubmenu(@"FCP Behavior", SKDebug_fcpBehaviorFlags());
    [root addItem:fcp];

    [root addItem:[NSMenuItem separatorItem]];

    // Log Level submenu (radio-style — current level always has a checkmark)
    NSMenu *logLevelMenu = [[NSMenu alloc] initWithTitle:@"Log Level"];
    logLevelMenu.autoenablesItems = YES;
    NSArray *levels = SKDebug_logLevelNames();
    for (NSInteger i = 0; i < (NSInteger)levels.count; i++) {
        NSMenuItem *item = [[NSMenuItem alloc]
            initWithTitle:[levels[i] capitalizedString]
                   action:@selector(setLogLevel:)
            keyEquivalent:@""];
        item.tag = i;
        item.target = ctl;
        [logLevelMenu addItem:item];
    }
    NSMenuItem *logLevelHeader = [[NSMenuItem alloc] initWithTitle:@"Log Level" action:nil keyEquivalent:@""];
    logLevelHeader.submenu = logLevelMenu;
    [root addItem:logLevelHeader];

    // LogUI / LogThread toggles
    NSMenuItem *logUI = [[NSMenuItem alloc]
        initWithTitle:@"Show In-App Log Panel"
               action:@selector(toggleBoolDefault:)
        keyEquivalent:@""];
    logUI.representedObject = @"LogUI";
    logUI.target = ctl;
    logUI.state = [[NSUserDefaults standardUserDefaults] boolForKey:@"LogUI"]
                  ? NSControlStateValueOn : NSControlStateValueOff;
    [root addItem:logUI];

    NSMenuItem *logThread = [[NSMenuItem alloc]
        initWithTitle:@"Include Thread Info in Log"
               action:@selector(toggleBoolDefault:)
        keyEquivalent:@""];
    logThread.representedObject = @"LogThread";
    logThread.target = ctl;
    logThread.state = [[NSUserDefaults standardUserDefaults] boolForKey:@"LogThread"]
                      ? NSControlStateValueOn : NSControlStateValueOff;
    [root addItem:logThread];

    [root addItem:[NSMenuItem separatorItem]];

    // Presets
    struct { NSString *title; NSString *key; } presets[] = {
        {@"Enable Timeline Visual Overlays", @"timeline_visual"},
        {@"Enable Timeline Logging",         @"timeline_logging"},
        {@"Enable Performance Monitoring",   @"performance"},
        {@"Enable Render Debug",             @"render_debug"},
        {@"Enable Verbose Logging",          @"verbose_logging"},
        {@"Reset All Debug Flags",           @"all_off"},
    };
    NSMenu *presetMenu = [[NSMenu alloc] initWithTitle:@"Presets"];
    for (size_t i = 0; i < sizeof(presets) / sizeof(presets[0]); i++) {
        NSMenuItem *item = [[NSMenuItem alloc]
            initWithTitle:presets[i].title
                   action:@selector(applyPreset:)
            keyEquivalent:@""];
        item.representedObject = presets[i].key;
        item.target = ctl;
        [presetMenu addItem:item];
    }
    NSMenuItem *presetHeader = [[NSMenuItem alloc] initWithTitle:@"Presets" action:nil keyEquivalent:@""];
    presetHeader.submenu = presetMenu;
    [root addItem:presetHeader];

    [root addItem:[NSMenuItem separatorItem]];

    // FCP-native developer actions
    NSMenu *fcpDevMenu = [[NSMenu alloc] initWithTitle:@"FCP Developer Tools"];
    {
        NSMenuItem *cg = [[NSMenuItem alloc]
            initWithTitle:@"Toggle CG Context Draw"
                   action:@selector(toggleCGContextDraw:)
            keyEquivalent:@""];
        cg.target = ctl;
        [fcpDevMenu addItem:cg];

        NSMenuItem *saveSearch = [[NSMenuItem alloc]
            initWithTitle:@"Toggle Save Search Results (VAML)"
                   action:@selector(toggleSaveSearchResults:)
            keyEquivalent:@""];
        saveSearch.target = ctl;
        [fcpDevMenu addItem:saveSearch];

        NSMenuItem *saveTrans = [[NSMenuItem alloc]
            initWithTitle:@"Toggle Save Transcription (VAML)"
                   action:@selector(toggleSaveTranscription:)
            keyEquivalent:@""];
        saveTrans.target = ctl;
        [fcpDevMenu addItem:saveTrans];
    }
    NSMenuItem *fcpDevHeader = [[NSMenuItem alloc] initWithTitle:@"FCP Developer Tools" action:nil keyEquivalent:@""];
    fcpDevHeader.submenu = fcpDevMenu;
    [root addItem:fcpDevHeader];

    [root addItem:[NSMenuItem separatorItem]];

    // Framerate monitor controls
    NSMenuItem *startFps = [[NSMenuItem alloc]
        initWithTitle:@"Start Framerate Monitor"
               action:@selector(startFramerateMonitor:)
        keyEquivalent:@""];
    startFps.target = ctl;
    [root addItem:startFps];

    NSMenuItem *stopFps = [[NSMenuItem alloc]
        initWithTitle:@"Stop Framerate Monitor"
               action:@selector(stopFramerateMonitor:)
        keyEquivalent:@""];
    stopFps.target = ctl;
    [root addItem:stopFps];

    // Top-level container
    NSMenuItem *topLevel = [[NSMenuItem alloc] initWithTitle:@"Debug" action:nil keyEquivalent:@""];
    topLevel.submenu = root;
    return topLevel;
}

static BOOL sDebugMenuInstalled = NO;

BOOL SpliceKit_installDebugMenuBar(void) {
    if (sDebugMenuInstalled) return YES;

    __block BOOL success = NO;
    dispatch_block_t work = ^{
        NSMenu *mainMenu = [NSApp mainMenu];
        if (!mainMenu) return;
        if ([mainMenu indexOfItemWithTitle:@"Debug"] >= 0) {
            sDebugMenuInstalled = YES;
            success = YES;
            return;
        }
        NSMenuItem *debugItem = SKDebug_buildDebugMenuItem();
        [SpliceKitDebugController shared].debugMenuItem = debugItem;

        // Insert before "Enhancements" (if present) or "Help".
        NSInteger insertIdx = [mainMenu indexOfItemWithTitle:@"Enhancements"];
        if (insertIdx < 0) insertIdx = [mainMenu indexOfItemWithTitle:@"Help"];
        if (insertIdx < 0) {
            [mainMenu addItem:debugItem];
        } else {
            [mainMenu insertItem:debugItem atIndex:insertIdx];
        }
        sDebugMenuInstalled = YES;
        success = YES;
        SpliceKit_log(@"Debug menu bar installed");
    };

    if ([NSThread isMainThread]) work(); else dispatch_sync(dispatch_get_main_queue(), work);
    return success;
}

BOOL SpliceKit_uninstallDebugMenuBar(void) {
    if (!sDebugMenuInstalled) return YES;
    __block BOOL success = NO;
    dispatch_block_t work = ^{
        NSMenu *mainMenu = [NSApp mainMenu];
        NSInteger idx = [mainMenu indexOfItemWithTitle:@"Debug"];
        if (idx >= 0) [mainMenu removeItemAtIndex:idx];
        [SpliceKitDebugController shared].debugMenuItem = nil;
        sDebugMenuInstalled = NO;
        success = YES;
    };
    if ([NSThread isMainThread]) work(); else dispatch_sync(dispatch_get_main_queue(), work);
    return success;
}

BOOL SpliceKit_isDebugMenuBarInstalled(void) {
    return sDebugMenuInstalled;
}
