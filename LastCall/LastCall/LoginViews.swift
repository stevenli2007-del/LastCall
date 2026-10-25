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

// MARK: - RootView

/// 登录闸门：没登录只看到登录页，登录后才是 TabView
struct RootView: View {
    @AppStorage(Session.key) private var hasLoggedIn = false

    var body: some View {
        if hasLoggedIn {
            ContentView()
        } else {
            LoginView()
        }
    }
}

// MARK: - LoginView

struct LoginView: View {
    @AppStorage(Session.key) private var hasLoggedIn = false

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
            Text("临期宝")
                .font(.title.weight(.bold))
            Text("便利店临期商品管理")
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
                TextField("手机号", text: $phone)
                    .keyboardType(.numberPad)
                    .textInputAutocapitalization(.never)
                    .font(.body.monospacedDigit())
                    .onChange(of: phone) { sanitizePhone() }
            }
            .padding(14)
            .background(.background, in: .rect(cornerRadius: 12))

            SecureField("密码（至少 6 位）", text: $password)
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
            Text("登录")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
        }
        .buttonStyle(.borderedProminent)
        .tint(Color.brandGreen)
        .disabled(trimmedPhone.isEmpty || password.isEmpty)
    }

    private var footer: some View {
        Text("演示版本：任意符合格式的手机号 + 6 位以上密码即可进入，账号体系尚未接入。")
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
            errorMessage = "请输入 11 位手机号（1 开头）"
            return
        }
        guard passwordOK else {
            errorMessage = "密码至少 6 位"
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
        Button("退出登录", role: .destructive) { confirming = true }
            .confirmationDialog("退出登录？", isPresented: $confirming, titleVisibility: .visible) {
                Button("退出", role: .destructive) { hasLoggedIn = false }
                Button("取消", role: .cancel) { }
            } message: {
                Text("回到登录页，库存数据不会丢失。")
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
