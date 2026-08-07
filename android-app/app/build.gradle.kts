plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "com.whisperbridge"
    compileSdk = 34

    defaultConfig {
        applicationId = "com.whisperbridge"
        minSdk = 26
        targetSdk = 34
        versionCode = 18
        versionName = "1.0.18"
    }

    signingConfigs {
        create("release") {
            val ksFile = project.findProperty("RELEASE_STORE_FILE") as? String
                ?: System.getenv("RELEASE_STORE_FILE")
            if (!ksFile.isNullOrEmpty()) {
                storeFile = rootProject.file(ksFile)
                storePassword = (project.findProperty("RELEASE_STORE_PASSWORD") as? String)
                    ?: System.getenv("RELEASE_STORE_PASSWORD") ?: ""
                keyAlias = (project.findProperty("RELEASE_KEY_ALIAS") as? String)
                    ?: System.getenv("RELEASE_KEY_ALIAS") ?: ""
                keyPassword = (project.findProperty("RELEASE_KEY_PASSWORD") as? String)
                    ?: System.getenv("RELEASE_KEY_PASSWORD") ?: ""
            }
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
            val ksFile = project.findProperty("RELEASE_STORE_FILE") as? String
                ?: System.getenv("RELEASE_STORE_FILE")
            if (!ksFile.isNullOrEmpty()) {
                signingConfig = signingConfigs.getByName("release")
            }
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_1_8
        targetCompatibility = JavaVersion.VERSION_1_8
    }

    kotlinOptions {
        jvmTarget = "1.8"
    }

    buildFeatures {
        viewBinding = true
    }
}

dependencies {
    implementation("androidx.core:core-ktx:1.12.0")
    implementation("androidx.appcompat:appcompat:1.6.1")
    implementation("com.google.android.material:material:1.11.0")
    implementation("androidx.constraintlayout:constraintlayout:2.1.4")
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.7.0")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.7.3")
    implementation("com.google.zxing:core:3.5.3")
    implementation("com.journeyapps:zxing-android-embedded:4.3.0")
}
