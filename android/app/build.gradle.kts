import org.jetbrains.kotlin.gradle.dsl.JvmTarget
import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
val webLoginTestBuild = !keystorePropertiesFile.exists() ||
    providers.gradleProperty("webLoginTestBuild").orNull == "true"
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

kotlin {
    compilerOptions {
        jvmTarget.set(JvmTarget.JVM_11)
    }
}

android {
    namespace = "com.anerycoft.coursehelper"
    compileSdkVersion("android-37.0")
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
        isCoreLibraryDesugaringEnabled = true
    }

    // 兼容百度地图定位
    packaging {
        jniLibs {
            keepDebugSymbols += "*/arm64-v8a/liblocSDK8b.so"
            keepDebugSymbols += "*/armeabi-v7a/liblocSDK8b.so"
            pickFirsts += "**/liblocSDK8b.so"
        }
    }

    defaultConfig {
        applicationId = "com.anerycoft.coursehelper"
        if (webLoginTestBuild) {
            applicationIdSuffix = ".weblogin"
            manifestPlaceholders["appLabel"] = "课程助手·网页登录测试"
        } else {
            manifestPlaceholders["appLabel"] = "Course Helper"
        }
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (webLoginTestBuild) {
            getByName("debug") {
                storeFile = rootProject.file("debug.keystore")
            }
        }
        if (keystorePropertiesFile.exists()) create("release") {
            keyAlias = keystoreProperties["keyAlias"] as String
            keyPassword = keystoreProperties["keyPassword"] as String
            storeFile = file(keystoreProperties["storeFile"] as String)
            storePassword = keystoreProperties["storePassword"] as String
        }
    }


    buildTypes {
        release {
            signingConfig = signingConfigs.getByName(if (webLoginTestBuild) "debug" else "release")
            // signingConfig = signingConfigs.getByName("debug")
            
            // 启用代码混淆
            isMinifyEnabled = true
            isShrinkResources = true

            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
            
            // 禁用 lint 检查以加快构建速度并避免文件锁定问题
            lint {
                checkDependencies = false
                abortOnError = false
            }
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
    implementation("com.baidu.lbsyun:BaiduMapSDK_Map:8.2.0")
    // flutter_bmflocation 插件已包含 BaiduMapSDK_Location_All
    implementation("com.baidu.lbsyun:BaiduMapSDK_Util:7.6.7")
}
