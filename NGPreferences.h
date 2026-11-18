#pragma once

#ifdef __cplusplus
extern "C" {
#endif

// 0: fixed, offline-baked glass (default); 1: on-demand GLSGlassView.
// The first read loads preferences; later reads use a thread-safe cached value.
int NGKeyboardRenderingMode(void);

// Reload the cached value without invoking the observer callback.
void NGKeyboardPreferencesReload(void);

// Call from the host process at startup. Registers exactly one Darwin observer
// per process and loads preferences. The first callback is retained for the
// process lifetime; subsequent Observe calls are ignored. Notifications reload
// preferences before invoking callback on the main queue. NULL is allowed.
void NGKeyboardPreferencesObserve(void (*callback)(void));

#ifdef __cplusplus
}
#endif
