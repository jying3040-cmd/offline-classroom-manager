#include "audio_player.h"

#pragma comment(lib, "mfplay.lib")
#pragma comment(lib, "mfplat.lib")
#pragma comment(lib, "mfuuid.lib")

// This machine's SDK subset ships mfplay.h and the .lib files but omits
// mfapi.h, so declare the one function and macros we need from it.
// Values match the canonical definitions in mfapi.h.
extern "C" HRESULT WINAPI MFStartup(ULONG version, DWORD flags);

#ifndef MF_VERSION
#define MF_VERSION (0x0002 << 16 | 0x0070)
#endif

#ifndef MFSTARTUP_LITE
#define MFSTARTUP_LITE 0x00000001
#endif

namespace {

bool EnsureMediaFoundationStarted() {
  static const bool started = [] {
    return SUCCEEDED(MFStartup(MF_VERSION, MFSTARTUP_LITE));
  }();
  return started;
}

}  // namespace

AudioPlayer::AudioPlayer() {
  EnsureMediaFoundationStarted();
}

AudioPlayer::~AudioPlayer() {
  CloseCurrent();
}

ULONG AudioPlayer::AddRef() {
  return InterlockedIncrement(&ref_);
}

ULONG AudioPlayer::Release() {
  const ULONG remaining = InterlockedDecrement(&ref_);
  if (remaining == 0) {
    delete this;
  }
  return remaining;
}

HRESULT AudioPlayer::QueryInterface(REFIID riid, void** ppv) {
  if (!ppv) {
    return E_POINTER;
  }
  if (riid == IID_IUnknown || riid == IID_IMFPMediaPlayerCallback) {
    *ppv = static_cast<IMFPMediaPlayerCallback*>(this);
    AddRef();
    return S_OK;
  }
  *ppv = nullptr;
  return E_NOINTERFACE;
}

void AudioPlayer::OnMediaPlayerEvent(MFP_EVENT_HEADER* event_header) {
  if (event_header &&
      event_header->eEventType == MFP_EVENT_TYPE_PLAYBACK_ENDED) {
    if (on_complete_) {
      on_complete_();
    }
  }
}

void AudioPlayer::SetOnComplete(std::function<void()> callback) {
  on_complete_ = std::move(callback);
}

HRESULT AudioPlayer::Play(const wchar_t* path) {
  CloseCurrent();
  if (!EnsureMediaFoundationStarted()) {
    return E_FAIL;
  }
  // MFPCreateMediaPlayer starts playback automatically when fStartPlayback
  // is TRUE (this SDK subset's entry point for MFPlay).
  return MFPCreateMediaPlayer(path, TRUE, MFP_OPTION_NONE, this, nullptr,
                              &player_);
}

HRESULT AudioPlayer::Pause() {
  return player_ ? player_->Pause() : E_FAIL;
}

HRESULT AudioPlayer::Resume() {
  return player_ ? player_->Play() : E_FAIL;
}

HRESULT AudioPlayer::Stop() {
  return player_ ? player_->Stop() : E_FAIL;
}

void AudioPlayer::Shutdown() {
  on_complete_ = nullptr;
  CloseCurrent();
}

void AudioPlayer::CloseCurrent() {
  if (player_) {
    player_->Shutdown();
    player_->Release();
    player_ = nullptr;
  }
}
