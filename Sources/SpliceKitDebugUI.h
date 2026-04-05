//
//  SpliceKitDebugUI.h
//  Recreates Final Cut Pro's hidden Debug preferences panel and Debug menu bar.
//
//  Apple strips PEAppDebugPreferencesModule.nib during release builds, so even
//  though the class is still compiled into FCP, the panel can never load at
//  runtime — `-[LKPreferences addPreferenceNamed:owner:]` silently filters it
//  out when the NIB fails to load.
//
//  SpliceKit rebuilds the view programmatically and registers it into
//  LKPreferences' internal state directly (bypassing the silent filter).
//  The Debug NSMenu is likewise reconstructed and inserted into NSApp.mainMenu.
//

#ifndef SpliceKitDebugUI_h
#define SpliceKitDebugUI_h

#import <Foundation/Foundation.h>

// Installs the Debug pane into FCP's Settings window.
// Returns YES on success. Must be called on the main thread.
BOOL SpliceKit_installDebugSettingsPanel(void);

// Removes the Debug pane from FCP's Settings window (if present).
BOOL SpliceKit_uninstallDebugSettingsPanel(void);

// Whether the Debug settings pane is currently installed.
BOOL SpliceKit_isDebugSettingsPanelInstalled(void);

// Installs the top-level "Debug" menu into the FCP menu bar.
// Returns YES on success. Must be called on the main thread.
BOOL SpliceKit_installDebugMenuBar(void);

// Removes the Debug menu bar item (if present).
BOOL SpliceKit_uninstallDebugMenuBar(void);

// Whether the Debug menu bar item is currently installed.
BOOL SpliceKit_isDebugMenuBarInstalled(void);

#endif /* SpliceKitDebugUI_h */
