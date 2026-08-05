import SwiftUI
import WebKit

/// 网页登录容器：内嵌 WKWebView 加载 v2ex.com/signin，用户像用浏览器一样
/// 登录（验证码、两步验证都正常）。登录成功后（URL 离开 /signin、/2fa），
/// 从 WebView 抓取完整会话 cookie 交给 `V2EXSessionStore`。
struct WebLoginView: UIViewRepresentable {
    /// 登录成功回调：cookie 字符串 + 用户名（从页面提取）。
    var onLoggedIn: (String, String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        webView.navigationDelegate = context.coordinator
        webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.5 Mobile/15E148 Safari/604.1"
        webView.load(URLRequest(url: URL(string: "https://www.v2ex.com/signin")!))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        private let parent: WebLoginView
        private var notified = false

        init(_ parent: WebLoginView) { self.parent = parent }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard !notified else { return }
            // 登录成功 = 离开登录流程页面（signin / 2fa）。
            let path = webView.url?.path ?? ""
            let isLoginFlow = path == "/signin" || path == "/2fa"
            guard !isLoginFlow else { return }

            // 用户名：登录后页面顶部有用户名菜单/头像。
            webView.evaluateJavaScript("""
                (function() {
                    var el = document.querySelector('.site-nav .top[href^="/member/"], #site-header-menu .avatar');
                    return el ? (el.getAttribute('alt') || el.getAttribute('href') || '') : '';
                })()
            """) { [weak self] result, _ in
                guard let self, !self.notified else { return }
                let username = (result as? String ?? "")
                    .replacingOccurrences(of: "/member/", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                // 抓完整会话 cookie（浏览器产生的，含 A2/A2O 等）。
                webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
                    guard !self.notified else { return }
                    self.notified = true
                    let v2exCookies = cookies.filter {
                        $0.domain.contains("v2ex.com")
                    }.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
                    guard !v2exCookies.isEmpty else { return }
                    DispatchQueue.main.async {
                        self.parent.onLoggedIn(v2exCookies, username)
                    }
                }
            }
        }
    }
}
