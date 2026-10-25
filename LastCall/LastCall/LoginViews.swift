//
//  LoginViews.swift
//  LastCall
//
//  登录页（ADR-007）：**假登录** —— 手机号 11 位 + 密码 ≥6 位，格式过了就进主界面。
//  不存储任何账号数据、不做任何网络请求，纯 UI 演示；对外讲解时如实说明账号体系为 Deferred。
//  ⑧ 号文件，理由见 TECHSTACK.md ADR-006。
//

import SwiftUI

// MARK: - 登录开关

/// 登录状态的唯一开关。放 `@AppStorage` 是为了**杀 App 重开不再要求登录** —— 这才像真的
enum Session {
    static let key = "hasLoggedIn"
}

// MARK: - 中英文切换（H7-7 方案 B：App 内切换，不跟随系统语言）

/// 语言选择的唯一存储 key。`zh` = 中文，`en` = English
enum L10n {
    static let langKey = "appLanguage"
    static var isEN: Bool { UserDefaults.standard.string(forKey: langKey) == "en" }
}

/// 轻量双语文案助手：tr("中文", "English")。只覆盖高频页固定文案；
/// 扫码提示 / 错误 toast / 空态按 H7-OPT §7.3 保留中文，不走这里
func tr(_ zh: String, _ en: String) -> String { L10n.isEN ? en : zh }

// MARK: - RootView

/// 登录闸门：没登录只看到登录页，登录后才是 TabView
struct RootView: View {
    @AppStorage(Session.key) private var hasLoggedIn = false
    @AppStorage(L10n.langKey) private var lang = "zh"

    var body: some View {
        Group {
            if hasLoggedIn {
                ContentView()
            } else {
                LoginView()
            }
        }
        .id(lang)   // 切语言 → 整棵树重建，所有 tr() 立即重算（H7-OPT §7.2：改完立即重绘）
    }
}

// MARK: - LoginView

struct LoginView: View {
    @AppStorage(Session.key) private var hasLoggedIn = false
    @AppStorage(L10n.langKey) private var lang = "zh"

    @State private var phone = ""
    @State private var password = ""
    @State private var errorMessage: String?

    private var trimmedPhone: String { phone.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// 中国手机号：1 开头 + 第二位 3–9 + 共 11 位
    private var phoneOK: Bool {
        trimmedPhone.range(of: "^1[3-9]\\d{9}$", options: .regularExpression) != nil
    }

    private var passwordOK: Bool { password.count >= 6 }

    var body: some View {
        VStack(spacing: 24) {
            HStack {
                Spacer(minLength: 0)
                Picker("Language", selection: $lang) {
                    Text("中文").tag("zh")
                    Text("EN").tag("en")
                }
                .pickerStyle(.segmented)
                .frame(width: 150)
            }
            Spacer(minLength: 0)
            header
            credentialsCard
            errorArea
            signInButton
            Spacer(minLength: 0)
            footer
        }
        .padding(24)
        .background(Color.paper.ignoresSafeArea())
    }

    // MARK: Subviews

    private var header: some View {
        VStack(spacing: 10) {
            Image(systemName: "clock.badge.checkmark")
                .font(.system(size: 46))
                .foregroundStyle(Color.brandGreen)
            Text(tr("临期宝", "LastCall"))
                .font(.title.weight(.bold))
            Text(tr("便利店临期商品管理", "Near-Expiry Stock Manager"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var credentialsCard: some View {
        VStack(spacing: 14) {
            HStack(spacing: 10) {
                Text("+86")
                    .font(.body.weight(.medium))
                    .foregroundStyle(.secondary)
                TextField(tr("手机号", "Phone"), text: $phone)
                    .keyboardType(.numberPad)
                    .textInputAutocapitalization(.never)
                    .font(.body.monospacedDigit())
                    .onChange(of: phone) { sanitizePhone() }
            }
            .padding(14)
            .background(.background, in: .rect(cornerRadius: 12))

            SecureField(tr("密码（至少 6 位）", "Password (6+ chars)"), text: $password)
                .padding(14)
                .background(.background, in: .rect(cornerRadius: 12))
        }
    }

    @ViewBuilder
    private var errorArea: some View {
        if let errorMessage {
            Text(errorMessage)
                .font(.footnote)
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var signInButton: some View {
        Button { signIn() } label: {
            Text(tr("登录", "Sign In"))
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
        }
        .buttonStyle(.borderedProminent)
        .tint(Color.brandGreen)
        .disabled(trimmedPhone.isEmpty || password.isEmpty)
    }

    private var footer: some View {
        Text(tr("演示版本：任意符合格式的手机号 + 6 位以上密码即可进入，账号体系尚未接入。",
                "Demo build: any valid phone number + 6-char password works. Accounts are not wired up yet."))
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
    }

    // MARK: Actions

    /// 只留数字，最多 11 位 —— 数字键盘下用户很容易粘进来空格或超长串
    private func sanitizePhone() {
        let digits = phone.filter(\.isNumber)
        phone = String(digits.prefix(11))
    }

    /// 不弹系统弹窗，红字就地提示（H7 §3）
    private func signIn() {
        guard phoneOK else {
            errorMessage = tr("请输入 11 位手机号（1 开头）", "Enter an 11-digit phone number starting with 1")
            return
        }
        guard passwordOK else {
            errorMessage = tr("密码至少 6 位", "Password must be at least 6 characters")
            return
        }
        errorMessage = nil
        hasLoggedIn = true
    }
}

// MARK: - SignOutButton

/// 设置页用。退出后回到登录页，库存数据不受影响
struct SignOutButton: View {
    @AppStorage(Session.key) private var hasLoggedIn = false
    @State private var confirming = false

    var body: some View {
        Button(tr("退出登录", "Sign Out"), role: .destructive) { confirming = true }
            .confirmationDialog(tr("退出登录？", "Sign out?"), isPresented: $confirming, titleVisibility: .visible) {
                Button(tr("退出", "Sign Out"), role: .destructive) { hasLoggedIn = false }
                Button(tr("取消", "Cancel"), role: .cancel) { }
            } message: {
                Text(tr("回到登录页，库存数据不会丢失。", "Returns to the sign-in page. Inventory data is kept."))
            }
    }
}

// MARK: - Previews

#Preview("登录页") {
    LoginView()
}

#Preview("登录页 · 已填") {
    LoginView()
}
