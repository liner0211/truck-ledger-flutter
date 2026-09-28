plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

import java.util.Properties
import java.io.FileInputStream

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("../../android/key.properties")
val localKeyProps = rootProject.file("key.properties")
val propsFile = when {
    localKeyProps.exists() -> localKeyProps
    keystorePropertiesFile.exists() -> keystorePropertiesFile
    else -> null
}
if (propsFile != null) {
    keystoreProperties.load(FileInputStream(propsFile))
}

android {
    namespace = "com.liner0211.truck_ledger_admin"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.liner0211.truck_ledger_admin"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (propsFile != null) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                val store = keystoreProperties["storeFile"] as String
                // parent key.properties uses path relative to main android/app
                storeFile = if (propsFile == keystorePropertiesFile) {
                    rootProject.file("../../android/app/" + store)
                } else {
                    file(store)
                }
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (propsFile != null) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
