// Demo host: links the OCaml LUI runtime (built by build-runtime.sh into
// lui_todos_runtime.o) to the Qt/QML backend. The OCaml side emits JSON
// patch batches through the patch callback; user events flow back through
// the lui_ocaml_* entry points.
#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQmlExtensionPlugin>
#include <QJsonDocument>
#include <QJsonObject>
#include <QVariantMap>

#include "lui_qml_backend.h"

Q_IMPORT_QML_PLUGIN(LuiPlugin)

extern "C" {
typedef void (*lui_patch_callback)(const char *json);
int32_t lui_ocaml_start(lui_patch_callback callback, int32_t platform_code,
                        int32_t host_code);
int32_t lui_ocaml_appear(int64_t node);
int32_t lui_ocaml_press(int64_t node);
int32_t lui_ocaml_long_press(int64_t node);
int32_t lui_ocaml_text_changed(int64_t node, const char *text);
int32_t lui_ocaml_submit(int64_t node);
int32_t lui_ocaml_dismiss(int64_t node);
int32_t lui_ocaml_double_press(int64_t node);
int32_t lui_ocaml_toggle_changed(int64_t node, int32_t checked);
int32_t lui_ocaml_radio_changed(int64_t node);
int32_t lui_ocaml_slider_changed(int64_t node, double fraction);
int32_t lui_ocaml_stop(void);
int32_t lui_ocaml_extension_event(int64_t node, const char *identifier,
                                  const char *name, const char *json_values);
}

namespace {
LUI::LuiQmlBackend *g_backend = nullptr;

void onPatch(const char *json) {
  if (g_backend != nullptr && json != nullptr && json[0] != '\0') {
    qDebug("LUI-PATCH %s", json);
    if (!g_backend->applyJson(QByteArray(json))) {
      qWarning("applyJson failed: %s", qPrintable(g_backend->lastError()));
    }
  }
}
} // namespace

int main(int argc, char *argv[]) {
  QGuiApplication app(argc, argv);

  LUI::ExtensionRegistry extensions;
  LUI::LuiQmlBackend backend(std::move(extensions));
  g_backend = &backend;

  QObject::connect(&backend, &LUI::LuiQmlBackend::luiEvent,
                   [](qint64 node, const QString &name,
                      const QVariantMap &payload) {
    qDebug("LUI-EVENT node=%lld name=%s payload=%s", (long long)node,
           qPrintable(name),
           qPrintable(QString::fromUtf8(QJsonDocument::fromVariant(payload)
                                        .toJson(QJsonDocument::Compact))));
    if (name == QLatin1String("press")) {
      lui_ocaml_press(node);
    } else if (name == QLatin1String("long-press")) {
      lui_ocaml_long_press(node);
    } else if (name == QLatin1String("double-press")) {
      lui_ocaml_double_press(node);
    } else if (name == QLatin1String("submit")) {
      lui_ocaml_submit(node);
    } else if (name == QLatin1String("dismiss")) {
      lui_ocaml_dismiss(node);
    } else if (name == QLatin1String("toggle-changed")) {
      lui_ocaml_toggle_changed(
          node, payload.value(QStringLiteral("checked")).toBool() ? 1 : 0);
    } else if (name == QLatin1String("change")) {
      lui_ocaml_radio_changed(node);
    } else if (name == QLatin1String("value-changed")) {
      lui_ocaml_slider_changed(
          node, payload.value(QStringLiteral("value")).toDouble());
    } else if (name == QLatin1String("text-changed")) {
      lui_ocaml_text_changed(
          node, qPrintable(payload.value(QStringLiteral("text")).toString()));
    } else if (name == QLatin1String("appear")) {
      lui_ocaml_appear(node);
    } else if (name == QLatin1String("extension")) {
      lui_ocaml_extension_event(
          node,
          qPrintable(payload.value(QStringLiteral("identifier")).toString()),
          qPrintable(payload.value(QStringLiteral("name")).toString()),
          qPrintable(QString::fromUtf8(QJsonDocument::fromVariant(
                       payload.value(QStringLiteral("values")))
                       .toJson(QJsonDocument::Compact))));
    }
  });

  // platform_code 4 = LinuxOS, host_code 4 = QMLHost.
  if (!lui_ocaml_start(&onPatch, 4, 4)) {
    qWarning("lui_ocaml_start failed");
    return 1;
  }

  QQmlApplicationEngine engine;
  backend.installImageProvider(&engine);
  engine.rootContext()->setContextProperty(QStringLiteral("luiBackend"),
                                           &backend);
  engine.rootContext()->setContextProperty(
      QStringLiteral("luiAppName"),
      qEnvironmentVariable("LUI_APP_NAME", "todos"));
  engine.addImportPath(QStringLiteral("qrc:/qt/qml"));
  engine.load(QUrl(QStringLiteral("qrc:/qt/qml/LuiDemo/main.qml")));
  if (engine.rootObjects().isEmpty()) return 2;

  const int code = app.exec();
  lui_ocaml_stop();
  g_backend = nullptr;
  return code;
}
