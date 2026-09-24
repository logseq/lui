/****************************************************************************
** Meta object code from reading C++ file 'lui_qml_backend.h'
**
** Created by: The Qt Meta Object Compiler version 68 (Qt 6.2.4)
**
** WARNING! All changes made in this file will be lost!
*****************************************************************************/

#include <memory>
#include "../../../../lib/lui_qml_backend.h"
#include <QtCore/qbytearray.h>
#include <QtCore/qmetatype.h>
#if !defined(Q_MOC_OUTPUT_REVISION)
#error "The header file 'lui_qml_backend.h' doesn't include <QObject>."
#elif Q_MOC_OUTPUT_REVISION != 68
#error "This file was generated using the moc from 6.2.4. It"
#error "cannot be used with the include files from this version of Qt."
#error "(The moc has changed too much.)"
#endif

QT_BEGIN_MOC_NAMESPACE
QT_WARNING_PUSH
QT_WARNING_DISABLE_DEPRECATED
struct qt_meta_stringdata_LUI__LuiQmlBackend_t {
    const uint offsetsAndSize[30];
    char stringdata0[154];
};
#define QT_MOC_LITERAL(ofs, len) \
    uint(offsetof(qt_meta_stringdata_LUI__LuiQmlBackend_t, stringdata0) + ofs), len 
static const qt_meta_stringdata_LUI__LuiQmlBackend_t qt_meta_stringdata_LUI__LuiQmlBackend = {
    {
QT_MOC_LITERAL(0, 18), // "LUI::LuiQmlBackend"
QT_MOC_LITERAL(19, 8), // "luiEvent"
QT_MOC_LITERAL(28, 0), // ""
QT_MOC_LITERAL(29, 4), // "node"
QT_MOC_LITERAL(34, 4), // "name"
QT_MOC_LITERAL(39, 7), // "payload"
QT_MOC_LITERAL(47, 17), // "generationChanged"
QT_MOC_LITERAL(65, 15), // "rootNodeChanged"
QT_MOC_LITERAL(81, 16), // "lastErrorChanged"
QT_MOC_LITERAL(98, 9), // "applyJson"
QT_MOC_LITERAL(108, 6), // "source"
QT_MOC_LITERAL(115, 10), // "generation"
QT_MOC_LITERAL(126, 8), // "rootNode"
QT_MOC_LITERAL(135, 8), // "LuiNode*"
QT_MOC_LITERAL(144, 9) // "lastError"

    },
    "LUI::LuiQmlBackend\0luiEvent\0\0node\0"
    "name\0payload\0generationChanged\0"
    "rootNodeChanged\0lastErrorChanged\0"
    "applyJson\0source\0generation\0rootNode\0"
    "LuiNode*\0lastError"
};
#undef QT_MOC_LITERAL

static const uint qt_meta_data_LUI__LuiQmlBackend[] = {

 // content:
      10,       // revision
       0,       // classname
       0,    0, // classinfo
       5,   14, // methods
       3,   57, // properties
       0,    0, // enums/sets
       0,    0, // constructors
       0,       // flags
       4,       // signalCount

 // signals: name, argc, parameters, tag, flags, initial metatype offsets
       1,    3,   44,    2, 0x06,    4 /* Public */,
       6,    0,   51,    2, 0x06,    8 /* Public */,
       7,    0,   52,    2, 0x06,    9 /* Public */,
       8,    0,   53,    2, 0x06,   10 /* Public */,

 // methods: name, argc, parameters, tag, flags, initial metatype offsets
       9,    1,   54,    2, 0x02,   11 /* Public */,

 // signals: parameters
    QMetaType::Void, QMetaType::LongLong, QMetaType::QString, QMetaType::QVariantMap,    3,    4,    5,
    QMetaType::Void,
    QMetaType::Void,
    QMetaType::Void,

 // methods: parameters
    QMetaType::Bool, QMetaType::QByteArray,   10,

 // properties: name, type, flags
      11, QMetaType::Int, 0x00015001, uint(1), 0,
      12, 0x80000000 | 13, 0x00015009, uint(2), 0,
      14, QMetaType::QString, 0x00015001, uint(3), 0,

       0        // eod
};

void LUI::LuiQmlBackend::qt_static_metacall(QObject *_o, QMetaObject::Call _c, int _id, void **_a)
{
    if (_c == QMetaObject::InvokeMetaMethod) {
        auto *_t = static_cast<LuiQmlBackend *>(_o);
        (void)_t;
        switch (_id) {
        case 0: _t->luiEvent((*reinterpret_cast< std::add_pointer_t<qint64>>(_a[1])),(*reinterpret_cast< std::add_pointer_t<QString>>(_a[2])),(*reinterpret_cast< std::add_pointer_t<QVariantMap>>(_a[3]))); break;
        case 1: _t->generationChanged(); break;
        case 2: _t->rootNodeChanged(); break;
        case 3: _t->lastErrorChanged(); break;
        case 4: { bool _r = _t->applyJson((*reinterpret_cast< std::add_pointer_t<QByteArray>>(_a[1])));
            if (_a[0]) *reinterpret_cast< bool*>(_a[0]) = std::move(_r); }  break;
        default: ;
        }
    } else if (_c == QMetaObject::IndexOfMethod) {
        int *result = reinterpret_cast<int *>(_a[0]);
        {
            using _t = void (LuiQmlBackend::*)(qint64 , const QString & , const QVariantMap & );
            if (*reinterpret_cast<_t *>(_a[1]) == static_cast<_t>(&LuiQmlBackend::luiEvent)) {
                *result = 0;
                return;
            }
        }
        {
            using _t = void (LuiQmlBackend::*)();
            if (*reinterpret_cast<_t *>(_a[1]) == static_cast<_t>(&LuiQmlBackend::generationChanged)) {
                *result = 1;
                return;
            }
        }
        {
            using _t = void (LuiQmlBackend::*)();
            if (*reinterpret_cast<_t *>(_a[1]) == static_cast<_t>(&LuiQmlBackend::rootNodeChanged)) {
                *result = 2;
                return;
            }
        }
        {
            using _t = void (LuiQmlBackend::*)();
            if (*reinterpret_cast<_t *>(_a[1]) == static_cast<_t>(&LuiQmlBackend::lastErrorChanged)) {
                *result = 3;
                return;
            }
        }
    } else if (_c == QMetaObject::RegisterPropertyMetaType) {
        switch (_id) {
        default: *reinterpret_cast<int*>(_a[0]) = -1; break;
        case 1:
            *reinterpret_cast<int*>(_a[0]) = qRegisterMetaType< LuiNode* >(); break;
        }
    }

#ifndef QT_NO_PROPERTIES
    else if (_c == QMetaObject::ReadProperty) {
        auto *_t = static_cast<LuiQmlBackend *>(_o);
        (void)_t;
        void *_v = _a[0];
        switch (_id) {
        case 0: *reinterpret_cast< int*>(_v) = _t->generation(); break;
        case 1: *reinterpret_cast< LuiNode**>(_v) = _t->rootNode(); break;
        case 2: *reinterpret_cast< QString*>(_v) = _t->lastError(); break;
        default: break;
        }
    } else if (_c == QMetaObject::WriteProperty) {
    } else if (_c == QMetaObject::ResetProperty) {
    } else if (_c == QMetaObject::BindableProperty) {
    }
#endif // QT_NO_PROPERTIES
}

const QMetaObject LUI::LuiQmlBackend::staticMetaObject = { {
    QMetaObject::SuperData::link<QObject::staticMetaObject>(),
    qt_meta_stringdata_LUI__LuiQmlBackend.offsetsAndSize,
    qt_meta_data_LUI__LuiQmlBackend,
    qt_static_metacall,
    nullptr,
qt_incomplete_metaTypeArray<qt_meta_stringdata_LUI__LuiQmlBackend_t
, QtPrivate::TypeAndForceComplete<int, std::true_type>, QtPrivate::TypeAndForceComplete<LuiNode*, std::true_type>, QtPrivate::TypeAndForceComplete<QString, std::true_type>, QtPrivate::TypeAndForceComplete<LuiQmlBackend, std::true_type>, QtPrivate::TypeAndForceComplete<void, std::false_type>, QtPrivate::TypeAndForceComplete<qint64, std::false_type>, QtPrivate::TypeAndForceComplete<const QString &, std::false_type>, QtPrivate::TypeAndForceComplete<const QVariantMap &, std::false_type>, QtPrivate::TypeAndForceComplete<void, std::false_type>, QtPrivate::TypeAndForceComplete<void, std::false_type>, QtPrivate::TypeAndForceComplete<void, std::false_type>

, QtPrivate::TypeAndForceComplete<bool, std::false_type>, QtPrivate::TypeAndForceComplete<const QByteArray &, std::false_type>

>,
    nullptr
} };


const QMetaObject *LUI::LuiQmlBackend::metaObject() const
{
    return QObject::d_ptr->metaObject ? QObject::d_ptr->dynamicMetaObject() : &staticMetaObject;
}

void *LUI::LuiQmlBackend::qt_metacast(const char *_clname)
{
    if (!_clname) return nullptr;
    if (!strcmp(_clname, qt_meta_stringdata_LUI__LuiQmlBackend.stringdata0))
        return static_cast<void*>(this);
    return QObject::qt_metacast(_clname);
}

int LUI::LuiQmlBackend::qt_metacall(QMetaObject::Call _c, int _id, void **_a)
{
    _id = QObject::qt_metacall(_c, _id, _a);
    if (_id < 0)
        return _id;
    if (_c == QMetaObject::InvokeMetaMethod) {
        if (_id < 5)
            qt_static_metacall(this, _c, _id, _a);
        _id -= 5;
    } else if (_c == QMetaObject::RegisterMethodArgumentMetaType) {
        if (_id < 5)
            *reinterpret_cast<QMetaType *>(_a[0]) = QMetaType();
        _id -= 5;
    }
#ifndef QT_NO_PROPERTIES
    else if (_c == QMetaObject::ReadProperty || _c == QMetaObject::WriteProperty
            || _c == QMetaObject::ResetProperty || _c == QMetaObject::BindableProperty
            || _c == QMetaObject::RegisterPropertyMetaType) {
        qt_static_metacall(this, _c, _id, _a);
        _id -= 3;
    }
#endif // QT_NO_PROPERTIES
    return _id;
}

// SIGNAL 0
void LUI::LuiQmlBackend::luiEvent(qint64 _t1, const QString & _t2, const QVariantMap & _t3)
{
    void *_a[] = { nullptr, const_cast<void*>(reinterpret_cast<const void*>(std::addressof(_t1))), const_cast<void*>(reinterpret_cast<const void*>(std::addressof(_t2))), const_cast<void*>(reinterpret_cast<const void*>(std::addressof(_t3))) };
    QMetaObject::activate(this, &staticMetaObject, 0, _a);
}

// SIGNAL 1
void LUI::LuiQmlBackend::generationChanged()
{
    QMetaObject::activate(this, &staticMetaObject, 1, nullptr);
}

// SIGNAL 2
void LUI::LuiQmlBackend::rootNodeChanged()
{
    QMetaObject::activate(this, &staticMetaObject, 2, nullptr);
}

// SIGNAL 3
void LUI::LuiQmlBackend::lastErrorChanged()
{
    QMetaObject::activate(this, &staticMetaObject, 3, nullptr);
}
QT_WARNING_POP
QT_END_MOC_NAMESPACE
