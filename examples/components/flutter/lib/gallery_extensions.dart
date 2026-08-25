import 'package:flutter/material.dart';
import 'package:lui_flutter_backend/lui_flutter_backend.dart';

LUIFlutterExtensionRegistry galleryExtensionRegistry() {
  return LUIFlutterExtensionRegistry()
    ..register(
      LUIFlutterExtension(
        identifier: 'native-card',
        fingerprint:
            'lui-extension-v1|11:native-card|profiles:android/flutter,'
            'ios/flutter,linux/flutter,macos/flutter,web/web,windows/flutter|'
            'standard-children:0|children:|properties:'
            '5:title:string:required:none|events:',
        properties: const [
          LUIExtensionProperty(
            name: 'title',
            kind: LUIExtensionValueKind.string,
            isRequired: true,
          ),
        ],
        builder: (context) =>
            _NativeGalleryCard(title: context.property('title')! as String),
      ),
    )
    ..registerTweak(
      LUIFlutterTweak(
        identifier: 'gallery-accent',
        fingerprint:
            'lui-tweak-v1|14:gallery-accent|profiles:android/flutter,'
            'ios/flutter,ios/swiftui,linux/flutter,macos/flutter,'
            'macos/swiftui,web/web,windows/flutter|properties:',
        builder: (content, _) => DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.lightBlue.shade50,
            border: Border.all(color: Colors.lightBlue.shade200),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(padding: const EdgeInsets.all(12), child: content),
        ),
      ),
    );
}

class _NativeGalleryCard extends StatefulWidget {
  const _NativeGalleryCard({required this.title});

  final String title;

  @override
  State<_NativeGalleryCard> createState() => _NativeGalleryCardState();
}

class _NativeGalleryCardState extends State<_NativeGalleryCard> {
  var _count = 0;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            Text('Host-owned presses: $_count'),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: () => setState(() => _count += 1),
              child: const Text('Update native state'),
            ),
          ],
        ),
      ),
    );
  }
}
