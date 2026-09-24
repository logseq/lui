// Ported from platform/flutter/test/lui_flutter_backend_test.dart — covers
// the wire apply pipeline (generation checks, atomic rejection, op handling)
// and event gating without needing a running QML scene.
#include <QSignalSpy>
#include <QTest>
#include <QVariantMap>

#include "lui_qml_backend.h"

using namespace LUI;

static QByteArray initialBatch() {
  return R"({"generation":1,"ops":[
      {"op":"create-node","id":1,"kind":"row"},
      {"op":"create-node","id":2,"kind":"text"},
      {"op":"set-prop","id":2,"property":"text","value":"Before"},
      {"op":"create-node","id":3,"kind":"button"},
      {"op":"set-prop","id":3,"property":"text","value":"Continue"},
      {"op":"set-prop","id":3,"property":"enabled","value":true},
      {"op":"insert-child","parent":1,"child":2,"index":0},
      {"op":"insert-child","parent":1,"child":3,"index":1}
    ]})";
}

class TestBackend : public QObject {
  Q_OBJECT

private slots:
  void removePropKeepsNode();
  void rejectsRootWithTwoChildren();
  void rejectsInvalidBatchAtomically();
  void rejectsSkippedGeneration();
  void rejectsDuplicateNodeIds();
  void propPatchBumpsOnlyThatNode();
  void childOpsReorder();
  void dropAttachedNodeRejected();
  void pressGate();
  void toggleGate();
  void eventRoundTrip();
  void extensionRegistryRules();
};

void TestBackend::removePropKeepsNode() {
  LuiQmlBackend backend({});
  QVERIFY(backend.applyJson(R"({"generation":1,"ops":[
      {"op":"create-node","id":1,"kind":"column"},
      {"op":"set-prop","id":1,"property":"padding","value":24}
    ]})"));
  QVERIFY(backend.applyJson(R"({"generation":2,"ops":[
      {"op":"remove-prop","id":1,"property":"padding"}
    ]})"));
  QCOMPARE(backend.generation(), 2);
  QVERIFY(backend.containsNode(1));
  QVERIFY(!backend.node(1)->properties().contains("padding"));
}

void TestBackend::rejectsRootWithTwoChildren() {
  LuiQmlBackend backend({});
  QVERIFY(!backend.applyJson(R"({"generation":1,"ops":[
      {"op":"create-node","id":1,"kind":"root"},
      {"op":"create-node","id":2,"kind":"text"},
      {"op":"create-node","id":3,"kind":"text"},
      {"op":"insert-child","parent":1,"child":2,"index":0},
      {"op":"insert-child","parent":1,"child":3,"index":1}
    ]})"));
  QVERIFY(!backend.lastError().isEmpty());
}

void TestBackend::rejectsInvalidBatchAtomically() {
  LuiQmlBackend backend({});
  QVERIFY(backend.applyJson(initialBatch()));
  QVERIFY(!backend.applyJson(R"({"generation":2,"ops":[
      {"op":"create-node","id":4,"kind":"text"},
      {"op":"insert-child","parent":99,"child":4,"index":0}
    ]})"));
  QVERIFY(!backend.containsNode(4));
  QCOMPARE(backend.generation(), 1);
}

void TestBackend::rejectsSkippedGeneration() {
  LuiQmlBackend backend({});
  QVERIFY(backend.applyJson(initialBatch()));
  QVERIFY(!backend.applyJson(R"({"generation":3,"ops":[
      {"op":"create-node","id":4,"kind":"text"}
    ]})"));
  QVERIFY(backend.lastError().contains("expected patch generation 2"));
  QVERIFY(!backend.containsNode(4));
  QCOMPARE(backend.generation(), 1);
}

void TestBackend::rejectsDuplicateNodeIds() {
  LuiQmlBackend backend({});
  QVERIFY(!backend.applyJson(R"({"generation":1,"ops":[
      {"op":"create-node","id":1,"kind":"text"},
      {"op":"create-node","id":1,"kind":"text"}
    ]})"));
}

void TestBackend::propPatchBumpsOnlyThatNode() {
  LuiQmlBackend backend({});
  QVERIFY(backend.applyJson(initialBatch()));
  const int rev1 = backend.node(1)->revision();
  const int rev3 = backend.node(3)->revision();
  QVERIFY(backend.applyJson(R"({"generation":2,"ops":[
      {"op":"set-prop","id":2,"property":"text","value":"Updated"}
    ]})"));
  QCOMPARE(backend.node(1)->revision(), rev1);
  QCOMPARE(backend.node(2)->revision(), 1);
  QCOMPARE(backend.node(3)->revision(), rev3);
  QCOMPARE(backend.node(2)->properties().value("text").toString(),
           QStringLiteral("Updated"));
}

void TestBackend::childOpsReorder() {
  LuiQmlBackend backend({});
  QVERIFY(backend.applyJson(initialBatch()));
  QVERIFY(backend.applyJson(R"({"generation":2,"ops":[
      {"op":"move-child","parent":1,"child":3,"index":0}
    ]})"));
  QCOMPARE(backend.node(1)->children().size(), 2);
  QVERIFY(backend.applyJson(R"({"generation":3,"ops":[
      {"op":"remove-child","parent":1,"child":2},
      {"op":"drop-node","id":2}
    ]})"));
  QCOMPARE(backend.node(1)->children().size(), 1);
  QVERIFY(!backend.containsNode(2));
}

void TestBackend::dropAttachedNodeRejected() {
  LuiQmlBackend backend({});
  QVERIFY(backend.applyJson(initialBatch()));
  QVERIFY(!backend.applyJson(R"({"generation":2,"ops":[
      {"op":"drop-node","id":2}
    ]})"));
  QVERIFY(backend.containsNode(2));
  QCOMPARE(backend.generation(), 1);
}

void TestBackend::pressGate() {
  LuiQmlBackend backend({});
  QVERIFY(backend.applyJson(initialBatch()));
  QSignalSpy spy(&backend, &LuiQmlBackend::luiEvent);
  // A plain text node is not pressable.
  QVERIFY(!backend.performPress(2));
  QCOMPARE(spy.size(), 0);
  QVERIFY(backend.applyJson(R"({"generation":2,"ops":[
      {"op":"set-prop","id":2,"property":"press-enabled","value":true}
    ]})"));
  QVERIFY(backend.performPress(2));
  QCOMPARE(spy.size(), 1);
  QCOMPARE(spy.first().at(1).toString(), QStringLiteral("press"));
}

void TestBackend::toggleGate() {
  LuiQmlBackend backend({});
  QVERIFY(backend.applyJson(R"({"generation":1,"ops":[
      {"op":"create-node","id":1,"kind":"checkbox"},
      {"op":"set-prop","id":1,"property":"text","value":"Opt in"}
    ]})"));
  QSignalSpy spy(&backend, &LuiQmlBackend::luiEvent);
  QVERIFY(backend.performToggle(1, true));
  QCOMPARE(spy.size(), 1);
  QCOMPARE(spy.first().at(1).toString(), QStringLiteral("toggle-changed"));
  QCOMPARE(spy.first().at(2).toMap().value("checked").toBool(), true);
}

void TestBackend::eventRoundTrip() {
  LuiQmlBackend backend({});
  QVERIFY(backend.applyJson(R"({"generation":1,"ops":[
      {"op":"create-node","id":1,"kind":"text-field"},
      {"op":"set-prop","id":1,"property":"text","value":"seed"}
    ]})"));
  QSignalSpy spy(&backend, &LuiQmlBackend::luiEvent);
  QVERIFY(backend.performTextChanged(1, QStringLiteral("hello")));
  QCOMPARE(spy.size(), 1);
  QCOMPARE(spy.first().at(1).toString(), QStringLiteral("text-changed"));
  QCOMPARE(spy.first().at(2).toMap().value("text").toString(),
           QStringLiteral("hello"));
}

void TestBackend::extensionRegistryRules() {
  ExtensionRegistry registry;
  // Extension identifiers cannot shadow standard node names.
  ExtensionSpec bad;
  bad.identifier = QStringLiteral("button");
  bad.fingerprint = QStringLiteral("shadow");
  bad.componentSource = QUrl(QStringLiteral("qrc:/bad.qml"));
  QString error;
  QVERIFY(!registry.add(bad, &error));

  ExtensionRegistry ok;
  ExtensionSpec spec;
  spec.identifier = QStringLiteral("native-card");
  spec.fingerprint = QStringLiteral("native-card-v1");
  spec.componentSource = QUrl(QStringLiteral("qrc:/NativeCard.qml"));
  QVERIFY2(ok.add(spec, &error), qPrintable(error));
  QVERIFY(ok.registration(QStringLiteral("native-card")) != nullptr);
  // Same fingerprint re-registers idempotently.
  QVERIFY(ok.add(spec, &error));
  spec.fingerprint = QStringLiteral("native-card-v2");
  QVERIFY(!ok.add(spec, &error));
}

QTEST_GUILESS_MAIN(TestBackend)
#include "tst_backend.moc"
