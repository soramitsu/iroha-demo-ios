import Foundation

extension Notification.Name {
    static let toriiWalletShouldRefresh = Notification.Name("toriiWalletShouldRefresh")
    static let toriiActiveAccountDidChange = Notification.Name("toriiActiveAccountDidChange")
    static let irohaWalletConnectDidStart = Notification.Name("irohaWalletConnectDidStart")
    static let irohaWalletConnectDidSign = Notification.Name("irohaWalletConnectDidSign")
    static let irohaWalletConnectDidReject = Notification.Name("irohaWalletConnectDidReject")
    static let irohaWalletConnectDidFail = Notification.Name("irohaWalletConnectDidFail")
}
