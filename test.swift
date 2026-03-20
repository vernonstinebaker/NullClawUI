import Foundation
struct foo {
    var role: String
    var optString: String? = UUID().uuidString
}
let a = foo(role: "ass")
print(a.optString)
