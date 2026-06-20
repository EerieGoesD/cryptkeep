#ifndef RUNNER_MS_STORE_BRIDGE_H_
#define RUNNER_MS_STORE_BRIDGE_H_

#include <flutter/flutter_engine.h>
#include <windows.h>

// Registers the "cryptkeep/ms_store" method channel that exposes Microsoft
// Store subscription add-on operations (query price, purchase, check active
// license) to Dart. |hwnd| is the top-level window used to anchor the Store
// purchase dialog, which is required for desktop apps.
void RegisterMsStoreChannel(flutter::FlutterEngine* engine, HWND hwnd);

#endif  // RUNNER_MS_STORE_BRIDGE_H_
