#!/usr/bin/env python3
"""Generate a self-contained Xcode project for Codex Meter."""

from __future__ import annotations

import os
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

CORE_FILES = [
    "Sources/CodexMeterCore/Models/AppSettings.swift",
    "Sources/CodexMeterCore/Models/CodexConnectionState.swift",
    "Sources/CodexMeterCore/Models/CodexErrors.swift",
    "Sources/CodexMeterCore/Models/CodexQuotaSnapshot.swift",
    "Sources/CodexMeterCore/Models/CodexRateLimitDTO.swift",
    "Sources/CodexMeterCore/Models/NotificationState.swift",
    "Sources/CodexMeterCore/Models/QuotaSeverity.swift",
    "Sources/CodexMeterCore/Models/UsagePace.swift",
    "Sources/CodexMeterCore/Services/CodexAppServerClient.swift",
    "Sources/CodexMeterCore/Services/CodexExecutableLocator.swift",
    "Sources/CodexMeterCore/Services/CodexQuotaParser.swift",
    "Sources/CodexMeterCore/Services/CodexQuotaService.swift",
    "Sources/CodexMeterCore/Services/HistoryStore.swift",
    "Sources/CodexMeterCore/Services/JSONValue.swift",
    "Sources/CodexMeterCore/Services/LaunchAtLoginService.swift",
    "Sources/CodexMeterCore/Services/NotificationService.swift",
    "Sources/CodexMeterCore/Utilities/CycleDetector.swift",
    "Sources/CodexMeterCore/Utilities/DateFormatting.swift",
    "Sources/CodexMeterCore/Utilities/Logger.swift",
    "Sources/CodexMeterCore/Utilities/PercentageFormatting.swift",
]

APP_FILES = [
    "Sources/CodexMeter/App/AppDelegate.swift",
    "Sources/CodexMeter/App/MenuBarIconRenderer.swift",
    "Sources/CodexMeter/App/SettingsWindowController.swift",
    "Sources/CodexMeter/App/StatusItemController.swift",
    "Sources/CodexMeter/ViewModels/QuotaViewModel.swift",
    "Sources/CodexMeter/ViewModels/SettingsViewModel.swift",
    "Sources/CodexMeter/Views/EmptyStateView.swift",
    "Sources/CodexMeter/Views/ErrorStateView.swift",
    "Sources/CodexMeter/Views/HeaderView.swift",
    "Sources/CodexMeter/Views/MenuBarContentView.swift",
    "Sources/CodexMeter/Views/PreviewSupport.swift",
    "Sources/CodexMeter/Views/QuotaHeroView.swift",
    "Sources/CodexMeter/Views/QuotaProgressView.swift",
    "Sources/CodexMeter/Views/SettingsView.swift",
    "Sources/CodexMeter/Views/Theme.swift",
    "Sources/CodexMeter/Views/UsagePaceView.swift",
    "Sources/CodexMeter/Views/UsageTrendView.swift",
]

TEST_FILES = [
    "Tests/CodexMeterCoreTests/CodexQuotaParserTests.swift",
    "Tests/CodexMeterCoreTests/HistoryStoreTests.swift",
    "Tests/CodexMeterCoreTests/NotificationPolicyTests.swift",
    "Tests/CodexMeterCoreTests/UsagePaceTests.swift",
]


def xid() -> str:
    return uuid.uuid4().hex[:24].upper()


IDS = {
    "project": xid(),
    "main_group": xid(),
    "app_target": xid(),
    "test_target": xid(),
    "app_product": xid(),
    "test_product": xid(),
    "sources_group": xid(),
    "core_group": xid(),
    "app_group": xid(),
    "tests_group": xid(),
    "resources_group": xid(),
    "products_group": xid(),
    "project_build": xid(),
    "app_build": xid(),
    "test_build": xid(),
    "resources_build": xid(),
    "frameworks_app": xid(),
    "frameworks_test": xid(),
    "sources_app_phase": xid(),
    "sources_test_phase": xid(),
    "resources_phase": xid(),
    "project_debug": xid(),
    "project_release": xid(),
    "app_debug": xid(),
    "app_release": xid(),
    "test_debug": xid(),
    "test_release": xid(),
    "info_plist": xid(),
    "entitlements": xid(),
    "assets": xid(),
}

file_ids = {}
build_ids = {}

for path in CORE_FILES + APP_FILES + TEST_FILES:
    file_ids[path] = xid()
    build_ids[path] = xid()


def file_ref(path: str) -> str:
    name = os.path.basename(path)
    return (
        f"\t\t{file_ids[path]} /* {name} */ = "
        f"{{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; "
        f"path = {name}; sourceTree = \"<group>\"; }};"
    )


def build_file(path: str) -> str:
    name = os.path.basename(path)
    return (
        f"\t\t{build_ids[path]} /* {name} in Sources */ = "
        f"{{isa = PBXBuildFile; fileRef = {file_ids[path]} /* {name} */; }};"
    )


def group_children(paths: list[str]) -> str:
    lines = []
    for path in paths:
        name = os.path.basename(path)
        lines.append(f"\t\t\t\t{file_ids[path]} /* {name} */,")
    return "\n".join(lines)


# Groups by folder for nicer Xcode navigation
core_model = [p for p in CORE_FILES if "/Models/" in p]
core_service = [p for p in CORE_FILES if "/Services/" in p]
core_util = [p for p in CORE_FILES if "/Utilities/" in p]
app_app = [p for p in APP_FILES if "/App/" in p]
app_vm = [p for p in APP_FILES if "/ViewModels/" in p]
app_views = [p for p in APP_FILES if "/Views/" in p]

group_ids = {
    "core_models": xid(),
    "core_services": xid(),
    "core_utils": xid(),
    "app_app": xid(),
    "app_vm": xid(),
    "app_views": xid(),
}

project = f"""// !$*UTF8*$!
{{
	archiveVersion = 1;
	classes = {{
	}};
	objectVersion = 56;
	objects = {{

/* Begin PBXBuildFile section */
{chr(10).join(build_file(p) for p in CORE_FILES + APP_FILES + TEST_FILES)}
		{IDS['assets']} /* Assets.xcassets in Resources */ = {{isa = PBXBuildFile; fileRef = {IDS['resources_build']} /* Assets.xcassets */; }};
/* End PBXBuildFile section */

/* Begin PBXFileReference section */
		{IDS['app_product']} /* CodexMeter.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = CodexMeter.app; sourceTree = BUILT_PRODUCTS_DIR; }};
		{IDS['test_product']} /* CodexMeterTests.xctest */ = {{isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = CodexMeterTests.xctest; sourceTree = BUILT_PRODUCTS_DIR; }};
		{IDS['info_plist']} /* Info.plist */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Info.plist; sourceTree = "<group>"; }};
		{IDS['entitlements']} /* CodexMeter.entitlements */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.entitlements; path = CodexMeter.entitlements; sourceTree = "<group>"; }};
		{IDS['resources_build']} /* Assets.xcassets */ = {{isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = Assets.xcassets; sourceTree = "<group>"; }};
{chr(10).join(file_ref(p) for p in CORE_FILES + APP_FILES + TEST_FILES)}
/* End PBXFileReference section */

/* Begin PBXFrameworksBuildPhase section */
		{IDS['frameworks_app']} /* Frameworks */ = {{
			isa = PBXFrameworksBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
		{IDS['frameworks_test']} /* Frameworks */ = {{
			isa = PBXFrameworksBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
/* End PBXFrameworksBuildPhase section */

/* Begin PBXGroup section */
		{IDS['main_group']} /* CodexMeter */ = {{
			isa = PBXGroup;
			children = (
				{IDS['core_group']} /* CodexMeterCore */,
				{IDS['app_group']} /* CodexMeter */,
				{IDS['tests_group']} /* CodexMeterTests */,
				{IDS['products_group']} /* Products */,
			);
			sourceTree = "<group>";
		}};
		{IDS['products_group']} /* Products */ = {{
			isa = PBXGroup;
			children = (
				{IDS['app_product']} /* CodexMeter.app */,
				{IDS['test_product']} /* CodexMeterTests.xctest */,
			);
			name = Products;
			sourceTree = "<group>";
		}};
		{IDS['core_group']} /* CodexMeterCore */ = {{
			isa = PBXGroup;
			children = (
				{group_ids['core_models']} /* Models */,
				{group_ids['core_services']} /* Services */,
				{group_ids['core_utils']} /* Utilities */,
			);
			name = CodexMeterCore;
			sourceTree = "<group>";
		}};
		{group_ids['core_models']} /* Models */ = {{
			isa = PBXGroup;
			children = (
{group_children(core_model)}
			);
			name = Models;
			path = Sources/CodexMeterCore/Models;
			sourceTree = "<group>";
		}};
		{group_ids['core_services']} /* Services */ = {{
			isa = PBXGroup;
			children = (
{group_children(core_service)}
			);
			name = Services;
			path = Sources/CodexMeterCore/Services;
			sourceTree = "<group>";
		}};
		{group_ids['core_utils']} /* Utilities */ = {{
			isa = PBXGroup;
			children = (
{group_children(core_util)}
			);
			name = Utilities;
			path = Sources/CodexMeterCore/Utilities;
			sourceTree = "<group>";
		}};
		{IDS['app_group']} /* CodexMeter */ = {{
			isa = PBXGroup;
			children = (
				{group_ids['app_app']} /* App */,
				{group_ids['app_vm']} /* ViewModels */,
				{group_ids['app_views']} /* Views */,
				{IDS['resources_group']} /* Resources */,
			);
			name = CodexMeter;
			sourceTree = "<group>";
		}};
		{group_ids['app_app']} /* App */ = {{
			isa = PBXGroup;
			children = (
{group_children(app_app)}
			);
			name = App;
			path = Sources/CodexMeter/App;
			sourceTree = "<group>";
		}};
		{group_ids['app_vm']} /* ViewModels */ = {{
			isa = PBXGroup;
			children = (
{group_children(app_vm)}
			);
			name = ViewModels;
			path = Sources/CodexMeter/ViewModels;
			sourceTree = "<group>";
		}};
		{group_ids['app_views']} /* Views */ = {{
			isa = PBXGroup;
			children = (
{group_children(app_views)}
			);
			name = Views;
			path = Sources/CodexMeter/Views;
			sourceTree = "<group>";
		}};
		{IDS['resources_group']} /* Resources */ = {{
			isa = PBXGroup;
			children = (
				{IDS['info_plist']} /* Info.plist */,
				{IDS['entitlements']} /* CodexMeter.entitlements */,
				{IDS['resources_build']} /* Assets.xcassets */,
			);
			name = Resources;
			path = Sources/CodexMeter/Resources;
			sourceTree = "<group>";
		}};
		{IDS['tests_group']} /* CodexMeterTests */ = {{
			isa = PBXGroup;
			children = (
{group_children(TEST_FILES)}
			);
			name = CodexMeterTests;
			path = Tests/CodexMeterCoreTests;
			sourceTree = "<group>";
		}};
/* End PBXGroup section */

/* Begin PBXNativeTarget section */
		{IDS['app_target']} /* CodexMeter */ = {{
			isa = PBXNativeTarget;
			buildConfigurationList = {IDS['app_build']} /* Build configuration list for PBXNativeTarget "CodexMeter" */;
			buildPhases = (
				{IDS['sources_app_phase']} /* Sources */,
				{IDS['frameworks_app']} /* Frameworks */,
				{IDS['resources_phase']} /* Resources */,
			);
			buildRules = (
			);
			dependencies = (
			);
			name = CodexMeter;
			productName = CodexMeter;
			productReference = {IDS['app_product']} /* CodexMeter.app */;
			productType = "com.apple.product-type.application";
		}};
		{IDS['test_target']} /* CodexMeterTests */ = {{
			isa = PBXNativeTarget;
			buildConfigurationList = {IDS['test_build']} /* Build configuration list for PBXNativeTarget "CodexMeterTests" */;
			buildPhases = (
				{IDS['sources_test_phase']} /* Sources */,
				{IDS['frameworks_test']} /* Frameworks */,
			);
			buildRules = (
			);
			dependencies = (
			);
			name = CodexMeterTests;
			productName = CodexMeterTests;
			productReference = {IDS['test_product']} /* CodexMeterTests.xctest */;
			productType = "com.apple.product-type.bundle.unit-test";
		}};
/* End PBXNativeTarget section */

/* Begin PBXProject section */
		{IDS['project']} /* Project object */ = {{
			isa = PBXProject;
			attributes = {{
				BuildIndependentTargetsInParallel = 1;
				LastSwiftUpdateCheck = 1500;
				LastUpgradeCheck = 1500;
				TargetAttributes = {{
					{IDS['app_target']} = {{
						CreatedOnToolsVersion = 15.0;
					}};
					{IDS['test_target']} = {{
						CreatedOnToolsVersion = 15.0;
					}};
				}};
			}};
			buildConfigurationList = {IDS['project_build']} /* Build configuration list for PBXProject "CodexMeter" */;
			compatibilityVersion = "Xcode 14.0";
			developmentRegion = en;
			hasScannedForEncodings = 0;
			knownRegions = (
				en,
				Base,
				"zh-Hans",
			);
			mainGroup = {IDS['main_group']};
			productRefGroup = {IDS['products_group']} /* Products */;
			projectDirPath = "";
			projectRoot = "";
			targets = (
				{IDS['app_target']} /* CodexMeter */,
				{IDS['test_target']} /* CodexMeterTests */,
			);
		}};
/* End PBXProject section */

/* Begin PBXResourcesBuildPhase section */
		{IDS['resources_phase']} /* Resources */ = {{
			isa = PBXResourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
				{IDS['assets']} /* Assets.xcassets in Resources */,
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
/* End PBXResourcesBuildPhase section */

/* Begin PBXSourcesBuildPhase section */
		{IDS['sources_app_phase']} /* Sources */ = {{
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
{chr(10).join(f"				{build_ids[p]} /* {os.path.basename(p)} in Sources */," for p in CORE_FILES + APP_FILES)}
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
		{IDS['sources_test_phase']} /* Sources */ = {{
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
{chr(10).join(f"				{build_ids[p]} /* {os.path.basename(p)} in Sources */," for p in CORE_FILES + TEST_FILES)}
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
/* End PBXSourcesBuildPhase section */

/* Begin XCBuildConfiguration section */
		{IDS['project_debug']} /* Debug */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
				ALWAYS_SEARCH_USER_PATHS = NO;
				CLANG_ENABLE_MODULES = YES;
				CLANG_ENABLE_OBJC_ARC = YES;
				COPY_PHASE_STRIP = NO;
				DEBUG_INFORMATION_FORMAT = dwarf;
				ENABLE_STRICT_OBJC_MSGSEND = YES;
				ENABLE_TESTABILITY = YES;
				GCC_DYNAMIC_NO_PIC = NO;
				GCC_OPTIMIZATION_LEVEL = 0;
				MACOSX_DEPLOYMENT_TARGET = 13.0;
				ONLY_ACTIVE_ARCH = YES;
				SDKROOT = macosx;
				SWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG;
				SWIFT_OPTIMIZATION_LEVEL = "-Onone";
				SWIFT_VERSION = 5.0;
			}};
			name = Debug;
		}};
		{IDS['project_release']} /* Release */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
				ALWAYS_SEARCH_USER_PATHS = NO;
				CLANG_ENABLE_MODULES = YES;
				CLANG_ENABLE_OBJC_ARC = YES;
				COPY_PHASE_STRIP = NO;
				DEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";
				ENABLE_NS_ASSERTIONS = NO;
				ENABLE_STRICT_OBJC_MSGSEND = YES;
				MACOSX_DEPLOYMENT_TARGET = 13.0;
				SDKROOT = macosx;
				SWIFT_COMPILATION_MODE = wholemodule;
				SWIFT_OPTIMIZATION_LEVEL = "-O";
				SWIFT_VERSION = 5.0;
			}};
			name = Release;
		}};
		{IDS['app_debug']} /* Debug */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
				ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
				CODE_SIGN_ENTITLEMENTS = Sources/CodexMeter/Resources/CodexMeter.entitlements;
				CODE_SIGN_IDENTITY = "-";
				CODE_SIGN_STYLE = Automatic;
				COMBINE_HIDPI_IMAGES = YES;
				CURRENT_PROJECT_VERSION = 1;
				ENABLE_APP_SANDBOX = NO;
				ENABLE_HARDENED_RUNTIME = NO;
				GENERATE_INFOPLIST_FILE = NO;
				INFOPLIST_FILE = Sources/CodexMeter/Resources/Info.plist;
				LD_RUNPATH_SEARCH_PATHS = (
					"$(inherited)",
					"@executable_path/../Frameworks",
				);
				MACOSX_DEPLOYMENT_TARGET = 13.0;
				MARKETING_VERSION = 1.0.0;
				PRODUCT_BUNDLE_IDENTIFIER = com.local.CodexMeter;
				PRODUCT_NAME = "$(TARGET_NAME)";
				SWIFT_EMIT_LOC_STRINGS = YES;
				SWIFT_VERSION = 5.0;
			}};
			name = Debug;
		}};
		{IDS['app_release']} /* Release */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
				ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
				CODE_SIGN_ENTITLEMENTS = Sources/CodexMeter/Resources/CodexMeter.entitlements;
				CODE_SIGN_IDENTITY = "-";
				CODE_SIGN_STYLE = Automatic;
				COMBINE_HIDPI_IMAGES = YES;
				CURRENT_PROJECT_VERSION = 1;
				ENABLE_APP_SANDBOX = NO;
				ENABLE_HARDENED_RUNTIME = NO;
				GENERATE_INFOPLIST_FILE = NO;
				INFOPLIST_FILE = Sources/CodexMeter/Resources/Info.plist;
				LD_RUNPATH_SEARCH_PATHS = (
					"$(inherited)",
					"@executable_path/../Frameworks",
				);
				MACOSX_DEPLOYMENT_TARGET = 13.0;
				MARKETING_VERSION = 1.0.0;
				PRODUCT_BUNDLE_IDENTIFIER = com.local.CodexMeter;
				PRODUCT_NAME = "$(TARGET_NAME)";
				SWIFT_EMIT_LOC_STRINGS = YES;
				SWIFT_VERSION = 5.0;
			}};
			name = Release;
		}};
		{IDS['test_debug']} /* Debug */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
				CODE_SIGN_IDENTITY = "-";
				CODE_SIGN_STYLE = Automatic;
				COMBINE_HIDPI_IMAGES = YES;
				GENERATE_INFOPLIST_FILE = YES;
				MACOSX_DEPLOYMENT_TARGET = 13.0;
				PRODUCT_BUNDLE_IDENTIFIER = com.local.CodexMeterTests;
				PRODUCT_NAME = "$(TARGET_NAME)";
				SWIFT_VERSION = 5.0;
			}};
			name = Debug;
		}};
		{IDS['test_release']} /* Release */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
				CODE_SIGN_IDENTITY = "-";
				CODE_SIGN_STYLE = Automatic;
				COMBINE_HIDPI_IMAGES = YES;
				GENERATE_INFOPLIST_FILE = YES;
				MACOSX_DEPLOYMENT_TARGET = 13.0;
				PRODUCT_BUNDLE_IDENTIFIER = com.local.CodexMeterTests;
				PRODUCT_NAME = "$(TARGET_NAME)";
				SWIFT_VERSION = 5.0;
			}};
			name = Release;
		}};
/* End XCBuildConfiguration section */

/* Begin XCConfigurationList section */
		{IDS['project_build']} /* Build configuration list for PBXProject "CodexMeter" */ = {{
			isa = XCConfigurationList;
			buildConfigurations = (
				{IDS['project_debug']} /* Debug */,
				{IDS['project_release']} /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		}};
		{IDS['app_build']} /* Build configuration list for PBXNativeTarget "CodexMeter" */ = {{
			isa = XCConfigurationList;
			buildConfigurations = (
				{IDS['app_debug']} /* Debug */,
				{IDS['app_release']} /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		}};
		{IDS['test_build']} /* Build configuration list for PBXNativeTarget "CodexMeterTests" */ = {{
			isa = XCConfigurationList;
			buildConfigurations = (
				{IDS['test_debug']} /* Debug */,
				{IDS['test_release']} /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		}};
/* End XCConfigurationList section */
	}};
	rootObject = {IDS['project']} /* Project object */;
}}
"""

# Fix project object ID clash: main group and project object used the same key.
# The PBXProject object should have a different ID than the main group.

out = ROOT / "CodexMeter.xcodeproj" / "project.pbxproj"
out.parent.mkdir(parents=True, exist_ok=True)
out.write_text(project)
print(f"Wrote {out}")
