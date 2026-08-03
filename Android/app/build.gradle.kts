plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

import java.util.Properties
import java.io.FileInputStream

android {
    namespace = "com.example.webviewdemo"
    compileSdk = 34

    buildFeatures {
        buildConfig = true
    }

    val envProperties = Properties()
    val envPropertiesFile = rootProject.file("../mock-server/env.properties")
    if (envPropertiesFile.exists()) {
        envProperties.load(FileInputStream(envPropertiesFile))
    }
    val mockServerIp = envProperties.getProperty("SERVER_IP", "")

    defaultConfig {
        applicationId = "com.example.webviewdemo"
        minSdk = 24
        targetSdk = 34
        versionCode = 1
        versionName = "1.0"
        
        buildConfigField("String", "SERVER_IP", "\"$mockServerIp\"")
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_1_8
        targetCompatibility = JavaVersion.VERSION_1_8
    }
    kotlinOptions {
        jvmTarget = "1.8"
    }
}

dependencies {
    implementation("androidx.core:core-ktx:1.12.0")
    implementation("androidx.appcompat:appcompat:1.6.1")
    implementation("com.google.android.material:material:1.10.0")
    implementation("androidx.constraintlayout:constraintlayout:2.1.4")
}
