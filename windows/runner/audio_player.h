#ifndef RUNNER_AUDIO_PLAYER_H_
#define RUNNER_AUDIO_PLAYER_H_

#include <mfplay.h>

#include <functional>

// Local audio player based on Media Foundation (MFPlay).
// Supports m4a/mp3/wav. Play/Pause/Resume/Stop must be called on the main
// thread; the completion callback arrives on an MF worker thread, so callers
// must marshal back to the main thread themselves.
class AudioPlayer : public IMFPMediaPlayerCallback {
 public:
  AudioPlayer();
  AudioPlayer(const AudioPlayer&) = delete;
  AudioPlayer& operator=(const AudioPlayer&) = delete;

  // IUnknown
  ULONG STDMETHODCALLTYPE AddRef() override;
  ULONG STDMETHODCALLTYPE Release() override;
  HRESULT STDMETHODCALLTYPE QueryInterface(REFIID riid, void** ppv) override;

  // IMFPMediaPlayerCallback
  void STDMETHODCALLTYPE OnMediaPlayerEvent(
      MFP_EVENT_HEADER* event_header) override;

  void SetOnComplete(std::function<void()> callback);

  // Plays a new file (stops the current playback first).
  HRESULT Play(const wchar_t* path);
  HRESULT Pause();
  HRESULT Resume();
  HRESULT Stop();

  // Clears the callback and stops playback; the object can then be freed
  // via Release().
  void Shutdown();

 private:
  ~AudioPlayer();

  void CloseCurrent();

  long ref_ = 1;
  IMFPMediaPlayer* player_ = nullptr;
  std::function<void()> on_complete_;
};

#endif  // RUNNER_AUDIO_PLAYER_H_
