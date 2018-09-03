//
//  AntiTrackingManager.swift
//  GhosteryLite
//
//  Created by Sahakyan on 8/9/18.
//  Copyright © 2018 Ghostery. All rights reserved.
//

import Foundation
import SafariServices
import RealmSwift

class AntiTrackingManager {

	static let shared = AntiTrackingManager()
	
	private var paused: Bool = false

	private let pauseNotificationName = Notification.Name(rawValue: "GhosteryIsPaused")
	private let resumeNotificationName = Notification.Name(rawValue: "GhosteryIsResumed")

	init() {
		let config = Realm.Configuration(
			// Set the new schema version. This must be greater than the previously used
			// version (if you've never set a schema version before, the version is 0).
			schemaVersion: 1,
			
			// Set the block which will be called automatically when opening a Realm with
			// a schema version lower than the one set above
			migrationBlock: { migration, oldSchemaVersion in
				// We haven’t migrated anything yet, so oldSchemaVersion == 0
				if (oldSchemaVersion < 1) {
					// Nothing to do!
					// Realm will automatically detect new properties and removed properties
					// And will update the schema on disk automatically
				}
		})
		
		// Tell Realm to use this new configuration object for the default Realm
		Realm.Configuration.defaultConfiguration = config
		let directory: URL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Constants.AppsGroupID)!
		let realmPath = directory.appendingPathComponent("db.realm")
		Realm.Configuration.defaultConfiguration.fileURL = realmPath
		let _ = try! Realm()
		GlobalConfigManager.shared.createConfigIfDoesNotExist()

		DistributedNotificationCenter.default().addObserver(self,
														selector: #selector(self.pause),
															name: Constants.PauseNotificationName, object: "Gh.GhosteryLite.SafariExtension")
		DistributedNotificationCenter.default().addObserver(self,
															selector: #selector(self.resume),
															name: Constants.ResumeNotificationName, object: "Gh.GhosteryLite.SafariExtension")
		DistributedNotificationCenter.default().addObserver(self,
															selector: #selector(self.switchToDefault),
															name: Constants.SwitchToDefaultNotificationName, object: "Gh.GhosteryLite.SafariExtension")
		DistributedNotificationCenter.default().addObserver(self,
															selector: #selector(self.switchToCustom),
															name: Constants.SwitchToCustomNotificationName, object: "Gh.GhosteryLite.SafariExtension")
	}

	func isPaused() -> Bool {
		return self.paused
	}

	func isDefaultConfigEnabled() -> Bool {
		if let c = GlobalConfigManager.shared.getCurrentConfig() {
			return c.configType.value == ConfigurationType.byDefault.rawValue
		}
		return true
	}

	@objc
	func pause() {
		self.paused = true
		reloadContentBlocker()
	}

	@objc
	func resume() {
		self.paused = false
		reloadContentBlocker()
	}

	@objc
	func switchToDefault() {
		GlobalConfigManager.shared.switchToConfig(.byDefault)
		let d = UserDefaults(suiteName: Constants.AppsGroupID)
		d?.set(true, forKey: "isDefault")
		d?.synchronize()
	}

	@objc
	func switchToCustom() {
		GlobalConfigManager.shared.switchToConfig(.custom)
		let d = UserDefaults(suiteName: Constants.AppsGroupID)
		d?.set(false, forKey: "isDefault")
		d?.synchronize()
	}

	func reloadContentBlocker() {
		if self.isPaused() {
			loadDummyCB()
		} else {
			if let c = GlobalConfigManager.shared.getCurrentConfig(),
				c.configType.value == ConfigurationType.custom.rawValue {
				self.loadCustomCB()
			} else {
				self.loadDefaultCB()
			}
		}
	}

	func trustDomain(domain: String) {
		TrustedSitesDataSource.shared.trustSite(domain)
	}

	func isTrustedDomain(domain: String) -> Bool {
		return TrustedSitesDataSource.shared.isTrusted(domain)
	}

	func getFilePath(fileName: String) -> URL? {
		return Bundle.main.url(forResource: fileName, withExtension: "json", subdirectory: "BlockListAssets/BlockListByCategory")
	}
	
	func getCategoryBlockListsFolder() -> String {
		return "BlockListAssets/BlockListByCategory"
//		return Bundle.main.url(forResource: fileName, withExtension: "json", subdirectory: )
	}

	func getBlockListsMainFolder() -> String {
		return "BlockListAssets"
	}

	private func loadCustomCB() {
		if let config = GlobalConfigManager.shared.getCurrentConfig() {
			var fileNames = [String]()
			if config.blockedCategories.count == 0 {
				loadDummyCB()
				return
			}
			for i in config.blockedCategories {
				if let c = CategoryType(rawValue: i) {
					fileNames.append(c.fileName())
				}
			}
			self.updateAndReloadBlockList(fileNames: fileNames, folderName: getCategoryBlockListsFolder())
		}
	}

	private func loadDefaultCB() {
		if let config = GlobalConfigManager.shared.getCurrentConfig() {
			var fileNames = [String]()
			for i in config.defaultBlockedCategories() {
				fileNames.append(i.fileName())
			}
			self.updateAndReloadBlockList(fileNames: fileNames, folderName: getCategoryBlockListsFolder())
		}
	}

	private func loadDummyCB() {
		self.updateAndReloadBlockList(fileNames: ["emptyRules"], folderName: getBlockListsMainFolder())
	}

	private func updateAndReloadBlockList(fileNames: [String], folderName: String) {
		BlockListFileManager.shared.generateCurrentBlockList(files: fileNames, folderName: folderName) {
			self.reloadCBExtension()
		}
	}

	private func reloadCBExtension() {
		SFContentBlockerManager.reloadContentBlocker(withIdentifier: "Gh.GhosteryLite.ContentBlocker", completionHandler: { (error) in
			if error != nil {
				print("Reloading Content Blocker is failed ---- \(error)")
			} else {
				print("Success!")
			}
		})
	}

	func contentBlokerRules() -> [NSItemProvider] {
		var resultRules = [NSItemProvider]()
		if let config =  GlobalConfigManager.shared.getCurrentConfig() {
			let blockedCategories = config.blockedCategories
			for i in blockedCategories {
				if let c = CategoryType(rawValue: i),
					let rulesURL = BlockListFileManager.shared.blockListURL(c),
					let ip = NSItemProvider(contentsOf: rulesURL) {
						return [ip]
//						resultRules.append(ip)
				}
			}
		}
		return resultRules
	}
}
