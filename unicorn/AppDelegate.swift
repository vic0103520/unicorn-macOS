import Cocoa
import InputMethodKit
import os

// Global server instances
var server: IMKServer?
var candidatesWindow: IMKCandidates?

@main
class AppDelegate: NSObject, NSApplicationDelegate {
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        let bundleID = Bundle.main.bundleIdentifier!
        
        server = IMKServer(name: bundleID + "_Connection", bundleIdentifier: bundleID)
        
        // Initialize the candidate window
        candidatesWindow = IMKCandidates(server: server, panelType: kIMKSingleColumnScrollingCandidatePanel)
    }
}
