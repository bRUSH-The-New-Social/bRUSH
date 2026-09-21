import SwiftUI
import AuthenticationServices
import GoogleSignInSwift

struct SignInProfileView: View {
    @ObservedObject var viewModel: ProfileViewModel
    @State private var showingSignUpFlow = false

    var body: some View {
        ZStack {
            // MARK: - Animated Background
            AnimatedSketchView()

            // MARK: - Foreground Content
            GeometryReader { geometry in
                VStack {
                    Spacer()

                    VStack(spacing: 20) {
                        Image("brush_logo_1")
                            .resizable()
                            .scaledToFit()
                            .frame(width: geometry.size.width * 0.35)
                            .padding(.bottom, 8)


                        InputField(placeholder: "Email", text: $viewModel.email, isSecure: false)
                        InputField(placeholder: "Password", text: $viewModel.password, isSecure: true)
                        
                        // Error message below password field with background
                        if let error = viewModel.errorMessage {
                            Text(error)
                                .foregroundColor(.red)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color.red.opacity(0.1))
                                .cornerRadius(8)
                                .transition(.opacity)
                        }

                        Button {
                            Task { await viewModel.signIn() }
                        } label: {
                            Text("Sign In")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.glassProminent)
                        
                        DividerWithText("or")
                        
                        VStack(spacing: 12) {
                            SignInWithAppleButton(.signIn) { request in
                                // Handled by AppleSignInHelper in AuthService
                            } onCompletion: { result in
                                // Ignored, as we launch the flow manually via the button overlay
                            }
                            .frame(height: 50)
                            .signInWithAppleButtonStyle(.black)
                            .cornerRadius(8)
                            .overlay {
                                // Overlay a clear button to trigger our custom view model method
                                Button(action: {
                                    Task { await viewModel.signInWithApple() }
                                }) {
                                    Color.clear
                                }
                            }
                            
                            Button(action: {
                                Task { await viewModel.signInWithGoogle() }
                            }) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color.white)
                                    
                                    HStack(spacing: 8) {
                                        Image("google_logo")
                                            .resizable()
                                            .scaledToFit()
                                            .frame(width: 18, height: 18)
                                        Text("Sign in with Google")
                                            .font(.system(size: 19, weight: .medium))
                                            .foregroundColor(.black)
                                    }
                                }
                                .frame(height: 50)
                            }
                        }
                    }
                    .frame(maxWidth: 340)
                    .padding(.horizontal)

                    Spacer()

                    Button {
                        showingSignUpFlow = true
                    } label: {
                        HStack {
                            Text("Don’t have an account?")
                            Text("Sign Up")
                                .fontWeight(.semibold)
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, 12)
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
                .sheet(isPresented: $showingSignUpFlow) {
                    SignUpFlow()
                }
            }
        }
    }
}
