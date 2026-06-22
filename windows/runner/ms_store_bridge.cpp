#include "ms_store_bridge.h"

#include <flutter/method_channel.h>
#include <flutter/method_result.h>
#include <flutter/standard_method_codec.h>

#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Windows.Services.Store.h>

#include <shobjidl_core.h>  // IInitializeWithWindow

#include <memory>
#include <string>
#include <variant>

using winrt::Windows::Services::Store::StoreAppLicense;
using winrt::Windows::Services::Store::StoreContext;
using winrt::Windows::Services::Store::StoreLicense;
using winrt::Windows::Services::Store::StoreProduct;
using winrt::Windows::Services::Store::StoreProductQueryResult;
using winrt::Windows::Services::Store::StorePurchaseResult;
using winrt::Windows::Services::Store::StorePurchaseStatus;

namespace {

// Subscription add-ons are queried with the "Durable" product kind.
const winrt::hstring kDurableKind = L"Durable";

// Kept alive for the lifetime of the app; the handler runs Store coroutines.
std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> g_channel;
HWND g_hwnd = nullptr;

using FlMethodResult = flutter::MethodResult<flutter::EncodableValue>;

std::string ToUtf8(winrt::hstring const& value) {
  return winrt::to_string(value);
}

std::string GetStringArg(const flutter::EncodableValue* args, const char* key) {
  if (const auto* map = std::get_if<flutter::EncodableMap>(args)) {
    auto it = map->find(flutter::EncodableValue(std::string(key)));
    if (it != map->end()) {
      if (const auto* str = std::get_if<std::string>(&it->second)) {
        return *str;
      }
    }
  }
  return std::string();
}

// Returns a StoreContext anchored to the app window so purchase UI can show.
StoreContext GetContext() {
  StoreContext context = StoreContext::GetDefault();
  auto interop = context.as<::IInitializeWithWindow>();
  interop->Initialize(g_hwnd);
  return context;
}

StoreProduct FindAddOn(StoreProductQueryResult const& query,
                       std::string const& product_id) {
  if (query.ExtendedError()) {
    return nullptr;
  }
  for (auto const& pair : query.Products()) {
    StoreProduct product = pair.Value();
    if (ToUtf8(product.InAppOfferToken()) == product_id) {
      return product;
    }
  }
  return nullptr;
}

std::string PurchaseStatusToString(StorePurchaseStatus status) {
  switch (status) {
    case StorePurchaseStatus::Succeeded:
      return "succeeded";
    case StorePurchaseStatus::AlreadyPurchased:
      return "alreadyPurchased";
    case StorePurchaseStatus::NotPurchased:
      return "notPurchased";
    case StorePurchaseStatus::NetworkError:
      return "networkError";
    case StorePurchaseStatus::ServerError:
      return "serverError";
    default:
      return "error";
  }
}

// Reports whether the user holds any active Pro subscription add-on. The app's
// only add-ons are the monthly and yearly Pro subscriptions, so any active
// add-on license grants Pro.
winrt::fire_and_forget HandleIsActive(
    std::shared_ptr<FlMethodResult> result) {
  winrt::apartment_context ui_thread;
  bool active = false;
  try {
    StoreContext context = GetContext();
    StoreAppLicense license = co_await context.GetAppLicenseAsync();
    for (auto const& pair : license.AddOnLicenses()) {
      StoreLicense addon = pair.Value();
      if (addon.IsActive()) {
        active = true;
        break;
      }
    }
  } catch (...) {
    active = false;
  }
  co_await ui_thread;
  result->Success(flutter::EncodableValue(active));
}

// Returns the localized formatted price of the add-on, or null on failure.
winrt::fire_and_forget HandleGetPrice(
    std::string product_id,
    std::shared_ptr<FlMethodResult> result) {
  winrt::apartment_context ui_thread;
  std::optional<std::string> price;
  try {
    StoreContext context = GetContext();
    StoreProductQueryResult query =
        co_await context.GetAssociatedStoreProductsAsync(
            winrt::single_threaded_vector<winrt::hstring>({kDurableKind}));
    StoreProduct product = FindAddOn(query, product_id);
    if (product) {
      price = ToUtf8(product.Price().FormattedPrice());
    }
  } catch (...) {
    price = std::nullopt;
  }
  co_await ui_thread;
  if (price.has_value()) {
    result->Success(flutter::EncodableValue(price.value()));
  } else {
    result->Success(flutter::EncodableValue());
  }
}

// Launches the Store purchase flow for the subscription add-on.
winrt::fire_and_forget HandlePurchase(
    std::string product_id,
    std::shared_ptr<FlMethodResult> result) {
  winrt::apartment_context ui_thread;
  std::string status;
  try {
    StoreContext context = GetContext();
    StoreProductQueryResult query =
        co_await context.GetAssociatedStoreProductsAsync(
            winrt::single_threaded_vector<winrt::hstring>({kDurableKind}));
    StoreProduct product = FindAddOn(query, product_id);
    if (!product) {
      co_await ui_thread;
      result->Success(flutter::EncodableValue(std::string("productNotFound")));
      co_return;
    }
    StorePurchaseResult purchase = co_await product.RequestPurchaseAsync();
    status = PurchaseStatusToString(purchase.Status());
  } catch (...) {
    status = "error";
  }
  co_await ui_thread;
  result->Success(flutter::EncodableValue(status));
}

}  // namespace

void RegisterMsStoreChannel(flutter::FlutterEngine* engine, HWND hwnd) {
  g_hwnd = hwnd;
  g_channel = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      engine->messenger(), "cryptkeep/ms_store",
      &flutter::StandardMethodCodec::GetInstance());

  g_channel->SetMethodCallHandler(
      [](const flutter::MethodCall<flutter::EncodableValue>& call,
         std::unique_ptr<FlMethodResult> result) {
        std::shared_ptr<FlMethodResult> shared_result = std::move(result);
        std::string product_id = GetStringArg(call.arguments(), "productId");
        const std::string& method = call.method_name();
        if (method == "isSubscriptionActive") {
          HandleIsActive(shared_result);
        } else if (method == "getPrice") {
          HandleGetPrice(product_id, shared_result);
        } else if (method == "purchaseSubscription") {
          HandlePurchase(product_id, shared_result);
        } else {
          shared_result->NotImplemented();
        }
      });
}
