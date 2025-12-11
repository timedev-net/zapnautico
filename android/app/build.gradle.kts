plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
    id("com.github.triplet.play")
}

android {
    namespace = "br.frota.zapnautico"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "br.frota.zapnautico"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            val keystorePath =
                System.getenv("ANDROID_KEYSTORE_PATH")
                    ?: project.findProperty("ANDROID_KEYSTORE_PATH") as? String
            val keystorePassword =
                System.getenv("ANDROID_KEYSTORE_PASSWORD")
                    ?: project.findProperty("ANDROID_KEYSTORE_PASSWORD") as? String
            val keyAliasValue =
                System.getenv("ANDROID_KEY_ALIAS")
                    ?: project.findProperty("ANDROID_KEY_ALIAS") as? String
            val keyPasswordValue =
                System.getenv("ANDROID_KEY_PASSWORD")
                    ?: project.findProperty("ANDROID_KEY_PASSWORD") as? String

            val hasReleaseKeystore = listOf(
                keystorePath,
                keystorePassword,
                keyAliasValue,
                keyPasswordValue,
            ).all { !it.isNullOrBlank() }

            if (hasReleaseKeystore) {
                storeFile = file(keystorePath!!)
                storePassword = keystorePassword
                keyAlias = keyAliasValue
                keyPassword = keyPasswordValue
            }
        }
    }

    buildTypes {
        release {
            // Falls back to the debug key locally if release signing variables are missing.
            signingConfig = signingConfigs
                .findByName("release")
                ?.takeIf { it.storeFile != null }
                ?: signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

play {
    val serviceAccountPath =
        System.getenv("PLAY_SERVICE_ACCOUNT_JSON")
            ?: project.findProperty("PLAY_SERVICE_ACCOUNT_JSON") as? String
    if (serviceAccountPath != null) {
        serviceAccountCredentials.set(file(serviceAccountPath))
    }

    track.set(
        System.getenv("PLAY_TRACK")
            ?: project.findProperty("PLAY_TRACK") as? String
            ?: "internal",
    )
    defaultToAppBundles.set(true)
}
