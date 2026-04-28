/*
 Copyright Soramitsu Co., Ltd. 2016 All Rights Reserved.
 http://soramitsu.co.jp
 
 Licensed under the Apache License, Version 2.0 (the "License");
 you may not use this file except in compliance with the License.
 You may obtain a copy of the License at
 
 http://www.apache.org/licenses/LICENSE-2.0
 
 Unless required by applicable law or agreed to in writing, software
 distributed under the License is distributed on an "AS IS" BASIS,
 WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 See the License for the specific language governing permissions and
 limitations under the License.
 */


import UIKit

extension UIColor {
    static var iroha: UIColor {
        UIColor { trait in
            if trait.userInterfaceStyle == .dark {
                return UIColor(red: 228.0 / 255.0, green: 35.0 / 255.0, blue: 45.0 / 255.0, alpha: 1)
            } else {
                return UIColor(red: 0.11, green: 0.34, blue: 0.61, alpha: 1)
            }
        }
    }

    static var irohaGreen: UIColor {
        UIColor(red: 120.0 / 255.0, green: 255.0 / 255.0, blue: 131.0 / 255.0, alpha: 1)
    }

    static var irohaYellow: UIColor {
        UIColor(red: 255.0 / 255.0, green: 228.0 / 255.0, blue: 75.0 / 255.0, alpha: 1)
    }

    static func hex(hex: String, alpha: CGFloat) -> UIColor {
        let sanitized = hex.replacingOccurrences(of: "#", with: "")
        var color: UInt64 = 0
        Scanner(string: sanitized).scanHexInt64(&color)
        let r = CGFloat((color & 0xFF0000) >> 16) / 255.0
        let g = CGFloat((color & 0x00FF00) >> 8) / 255.0
        let b = CGFloat(color & 0x0000FF) / 255.0
        return UIColor(red: r, green: g, blue: b, alpha: alpha)
    }
}
