part of '../beariscope_modal.dart';

class _ModalPrimaryIconButton extends StatelessWidget {
  const _ModalPrimaryIconButton({required this.action});

  final BeariscopeModalPrimaryAction action;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return IconButton(
      tooltip: action.label,
      onPressed: action.enabled && !action.loading ? action.onPressed : null,
      style: IconButton.styleFrom(
        backgroundColor: colors.primary,
        foregroundColor: colors.onPrimary,
      ),
      icon: Stack(
        alignment: Alignment.center,
        children: [
          // Retain the themed icon's footprint while the spinner is visible.
          Opacity(opacity: action.loading ? 0 : 1, child: Icon(action.icon)),
          if (action.loading)
            const Positioned.fill(child: Center(child: _ModalActionProgress())),
        ],
      ),
    );
  }
}

class _ModalActionProgress extends StatelessWidget {
  const _ModalActionProgress();

  @override
  Widget build(BuildContext context) => const SizedBox.square(
    dimension: 18,
    child: CircularProgressIndicator(strokeWidth: 2),
  );
}
