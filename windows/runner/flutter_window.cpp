#include "flutter_window.h"

#include <optional>

#include "flutter/generated_plugin_registrant.h"

namespace {

// Custom message: MF worker thread callback -> PostMessage -> main thread
// notifies Dart.
constexpr UINT kAudioCompletedMessage = WM_APP + 0x531;

std::wstring ToWide(const std::string& utf8) {
  if (utf8.empty()) {
    return {};
  }
  const int size = MultiByteToWideChar(CP_UTF8, 0, utf8.c_str(),
                                       static_cast<int>(utf8.size()), nullptr, 0);
  std::wstring wide(size, L'\0');
  MultiByteToWideChar(CP_UTF8, 0, utf8.c_str(), static_cast<int>(utf8.size()),
                      wide.data(), size);
  return wide;
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  InitAudio();
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  if (audio_player_) {
    audio_player_->Shutdown();
    audio_player_->Release();
    audio_player_ = nullptr;
  }
  if (audio_channel_) {
    audio_channel_->SetMethodCallHandler(nullptr);
    audio_channel_.reset();
  }
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

void FlutterWindow::InitAudio() {
  audio_player_ = new AudioPlayer();
  audio_player_->SetOnComplete([this]() {
    // MF worker thread: post a message only; Dart is notified on the main
    // thread from MessageHandler.
    PostMessage(GetHandle(), kAudioCompletedMessage, 0, 0);
  });
  audio_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), "classroom/audio",
          &flutter::StandardMethodCodec::GetInstance());
  audio_channel_->SetMethodCallHandler(
      [this](const auto& call, auto result) {
        HandleAudioCall(call, std::move(result));
      });
}

void FlutterWindow::HandleAudioCall(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const std::string& method = call.method_name();
  if (method == "play") {
    const auto* path = std::get_if<std::string>(call.arguments());
    if (!path || path->empty() || !audio_player_) {
      result->Error("bad_args", "path required");
      return;
    }
    if (SUCCEEDED(audio_player_->Play(ToWide(*path).c_str()))) {
      result->Success();
    } else {
      result->Error("play_failed", "cannot play file");
    }
  } else if (method == "pause") {
    if (audio_player_ && SUCCEEDED(audio_player_->Pause())) {
      result->Success();
    } else {
      result->Error("pause_failed", "pause failed");
    }
  } else if (method == "resume") {
    if (audio_player_ && SUCCEEDED(audio_player_->Resume())) {
      result->Success();
    } else {
      result->Error("resume_failed", "resume failed");
    }
  } else if (method == "stop") {
    if (audio_player_ && SUCCEEDED(audio_player_->Stop())) {
      result->Success();
    } else {
      result->Error("stop_failed", "stop failed");
    }
  } else {
    result->NotImplemented();
  }
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
    case kAudioCompletedMessage:
      if (audio_channel_) {
        audio_channel_->InvokeMethod("completed", nullptr);
      }
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
