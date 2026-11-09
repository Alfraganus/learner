import 'package:flutter/material.dart';

import 'common.dart';

/// Claude'dan keladigan kontentni yuklash: kutish, xato va qayta yaratish holatlari bilan.
class AsyncLoader<T> extends StatefulWidget {
  const AsyncLoader({
    super.key,
    required this.load,
    required this.loadingText,
    required this.builder,
    this.loadingHint,
  });

  final String? loadingHint;

  final Future<T> Function(bool force) load;
  final String loadingText;
  final Widget Function(BuildContext context, T data, VoidCallback regenerate) builder;

  @override
  State<AsyncLoader<T>> createState() => _AsyncLoaderState<T>();
}

class _AsyncLoaderState<T> extends State<AsyncLoader<T>> {
  late Future<T> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.load(false);
  }

  void _reload(bool force) => setState(() => _future = widget.load(force));

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<T>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return LoadingView(widget.loadingText, hint: widget.loadingHint);
        }
        if (snap.hasError) {
          return ErrorView('${snap.error}', onRetry: () => _reload(false));
        }
        return widget.builder(context, snap.data as T, () => _reload(true));
      },
    );
  }
}
