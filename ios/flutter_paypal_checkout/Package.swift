// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "flutter_paypal_checkout",
    platforms: [
        .iOS("16.0")
    ],
    products: [
        .library(name: "flutter-paypal-checkout", targets: ["flutter_paypal_checkout"])
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework"),
        .package(url: "https://github.com/paypal/paypal-ios.git", from: "3.1.1")
    ],
    targets: [
        .target(
            name: "flutter_paypal_checkout",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework"),
                .product(name: "CorePayments", package: "paypal-ios"),
                .product(name: "PayPalPayments", package: "paypal-ios"),
                .product(name: "CardPayments", package: "paypal-ios")
            ],
        )
    ]
)
