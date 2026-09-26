#include "lui_split_extensions.h"

namespace LUI {
namespace {

ExtensionProperty prop(const QString &name, ExtensionValueKind kind,
                       bool required = false) {
  ExtensionProperty p;
  p.name = name;
  p.kind = kind;
  p.isRequired = required;
  return p;
}

ExtensionEventSchema event(const QString &name,
                           QVector<ExtensionEventField> fields = {}) {
  ExtensionEventSchema e;
  e.name = name;
  e.fields = std::move(fields);
  return e;
}

ExtensionEventField field(const QString &name, ExtensionValueKind kind,
                          bool required = false) {
  ExtensionEventField f;
  f.name = name;
  f.kind = kind;
  f.isRequired = required;
  return f;
}

QUrl qmlSource(const char *file) {
  return QUrl(QStringLiteral("qrc:/qt/qml/Lui/") + QLatin1String(file));
}

} // namespace

bool registerSplitExtensions(ExtensionRegistry &registry, QString *error) {
  {
    ExtensionSpec spec;
    spec.identifier = QStringLiteral("split-view");
    spec.fingerprint = QStringLiteral("lui-extension-v1|10:split-view|profiles:android/flutter,ios/flutter,ios/swiftui,linux/flutter,linux/qml,macos/flutter,macos/qml,macos/swiftui,web/web,windows/flutter,windows/qml,windows/winui|standard-children:0|children:12:split-branch,10:split-pane|properties:17:divider-thickness:float:optional:none,24:accessibility-identifier:string:optional:none,9:animation:bool:optional:none|events:");
    spec.componentSource = qmlSource("LuiSplitView.qml");
    spec.childIdentifiers = {QStringLiteral("split-branch"),
                             QStringLiteral("split-pane")};
    spec.properties = {
        prop(QStringLiteral("divider-thickness"), ExtensionValueKind::Double),
        prop(QStringLiteral("animation"), ExtensionValueKind::Boolean),
        prop(QStringLiteral("accessibility-identifier"),
             ExtensionValueKind::String),
    };
    if (!registry.add(spec, error))
      return false;
  }
  {
    ExtensionSpec spec;
    spec.identifier = QStringLiteral("split-branch");
    spec.fingerprint = QStringLiteral("lui-extension-v1|12:split-branch|profiles:android/flutter,ios/flutter,ios/swiftui,linux/flutter,linux/qml,macos/flutter,macos/qml,macos/swiftui,web/web,windows/flutter,windows/qml,windows/winui|standard-children:0|children:12:split-branch,10:split-pane|properties:11:orientation:string:required:none,5:ratio:float:required:none|events:13:ratio-changed[5:ratio:float:required]");
    spec.componentSource = qmlSource("LuiSplitBranch.qml");
    spec.childIdentifiers = {QStringLiteral("split-branch"),
                             QStringLiteral("split-pane")};
    spec.properties = {
        prop(QStringLiteral("orientation"), ExtensionValueKind::String, true),
        prop(QStringLiteral("ratio"), ExtensionValueKind::Double, true),
    };
    spec.events = {
        event(QStringLiteral("ratio-changed"),
              {field(QStringLiteral("ratio"), ExtensionValueKind::Double,
                     true)}),
    };
    if (!registry.add(spec, error))
      return false;
  }
  {
    ExtensionSpec spec;
    spec.identifier = QStringLiteral("split-pane");
    spec.fingerprint = QStringLiteral("lui-extension-v1|10:split-pane|profiles:android/flutter,ios/flutter,ios/swiftui,linux/flutter,linux/qml,macos/flutter,macos/qml,macos/swiftui,web/web,windows/flutter,windows/qml,windows/winui|standard-children:0|children:9:split-tab|properties:24:accessibility-identifier:string:optional:none,7:focused:bool:optional:none,7:pane-id:string:required:none,8:selected:string:optional:none|events:10:split-drop[3:tab:string:required,4:edge:string:required,9:from-pane:string:required],10:tab-closed[3:tab:string:required],11:pane-closed[],12:pane-focused[],12:tab-selected[3:tab:string:required],15:split-requested[11:orientation:string:required],8:navigate[9:direction:string:required],9:tab-moved[3:tab:string:required,5:index:int:required,9:from-pane:string:required]");
    spec.componentSource = qmlSource("LuiSplitPane.qml");
    spec.childIdentifiers = {QStringLiteral("split-tab")};
    spec.properties = {
        prop(QStringLiteral("pane-id"), ExtensionValueKind::String, true),
        prop(QStringLiteral("selected"), ExtensionValueKind::String),
        prop(QStringLiteral("focused"), ExtensionValueKind::Boolean),
        prop(QStringLiteral("accessibility-identifier"),
             ExtensionValueKind::String),
    };
    spec.events = {
        event(QStringLiteral("tab-selected"),
              {field(QStringLiteral("tab"), ExtensionValueKind::String, true)}),
        event(QStringLiteral("tab-closed"),
              {field(QStringLiteral("tab"), ExtensionValueKind::String, true)}),
        event(QStringLiteral("tab-moved"),
              {field(QStringLiteral("tab"), ExtensionValueKind::String, true),
               field(QStringLiteral("index"), ExtensionValueKind::Integer,
                     true),
               field(QStringLiteral("from-pane"), ExtensionValueKind::String,
                     true)}),
        event(QStringLiteral("pane-focused")),
        event(QStringLiteral("navigate"),
              {field(QStringLiteral("direction"), ExtensionValueKind::String,
                     true)}),
        event(QStringLiteral("split-requested"),
              {field(QStringLiteral("orientation"), ExtensionValueKind::String,
                     true)}),
        event(QStringLiteral("split-drop"),
              {field(QStringLiteral("tab"), ExtensionValueKind::String, true),
               field(QStringLiteral("from-pane"), ExtensionValueKind::String,
                     true),
               field(QStringLiteral("edge"), ExtensionValueKind::String,
                     true)}),
        event(QStringLiteral("pane-closed")),
    };
    if (!registry.add(spec, error))
      return false;
  }
  {
    ExtensionSpec spec;
    spec.identifier = QStringLiteral("split-tab");
    spec.fingerprint = QStringLiteral("lui-extension-v1|9:split-tab|profiles:android/flutter,ios/flutter,ios/swiftui,linux/flutter,linux/qml,macos/flutter,macos/qml,macos/swiftui,web/web,windows/flutter,windows/qml,windows/winui|standard-children:1|children:|properties:24:accessibility-identifier:string:optional:none,4:icon:string:optional:none,5:dirty:bool:optional:none,5:title:string:required:none,6:tab-id:string:required:none,8:closable:bool:optional:none|events:");
    spec.componentSource = qmlSource("LuiSplitTab.qml");
    spec.acceptsStandardChildren = true;
    spec.properties = {
        prop(QStringLiteral("tab-id"), ExtensionValueKind::String, true),
        prop(QStringLiteral("title"), ExtensionValueKind::String, true),
        prop(QStringLiteral("icon"), ExtensionValueKind::String),
        prop(QStringLiteral("dirty"), ExtensionValueKind::Boolean),
        prop(QStringLiteral("closable"), ExtensionValueKind::Boolean),
        prop(QStringLiteral("accessibility-identifier"),
             ExtensionValueKind::String),
    };
    if (!registry.add(spec, error))
      return false;
  }
  return true;
}

} // namespace LUI
