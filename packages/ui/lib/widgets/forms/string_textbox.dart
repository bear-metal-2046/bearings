import 'package:flutter/material.dart';

import 'form_style.dart';

class StringTextbox extends StatefulWidget {
  const StringTextbox({
    super.key,
    this.fillColor,
    required this.onChanged,
    this.outlineColor,
    required this.dataName,
    required this.width,
    required this.height,
    this.initialString,
  });

  final Color? fillColor;
  final Color? outlineColor;
  final String dataName;
  final ValueChanged<String> onChanged;
  final double width;
  final double height;
  final String? initialString;

  @override
  State<StringTextbox> createState() => _StringTextboxState();
}

class _StringTextboxState extends State<StringTextbox> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _controller.text = widget.initialString ?? '';
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant StringTextbox oldWidget) {
    super.didUpdateWidget(oldWidget);
    final externalValue = widget.initialString ?? '';
    if (oldWidget.initialString != widget.initialString &&
        !_focusNode.hasFocus &&
        _controller.text != externalValue) {
      _controller.value = _controller.value.copyWith(
        text: externalValue,
        selection: TextSelection.collapsed(offset: externalValue.length),
        composing: TextRange.empty,
      );
    }
  }

  InputDecoration _decoration(BuildContext context) {
    return FormWidgetStyle.textFieldDecoration(
      context: context,
      label: widget.dataName,
      fillColor: widget.fillColor,
      outlineColor: widget.outlineColor,
    );
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Taller slots from the JSON layout behave like true notes fields.
          final isMultiline = constraints.maxHeight >= 88;

          return TextField(
            cursorColor: Theme.of(context).colorScheme.onSurface,
            style: Theme.of(context).textTheme.bodyMedium,
            focusNode: _focusNode,
            keyboardType: isMultiline
                ? TextInputType.multiline
                : TextInputType.text,
            textInputAction: isMultiline
                ? TextInputAction.newline
                : TextInputAction.done,
            minLines: isMultiline ? null : 1,
            maxLines: isMultiline ? null : 1,
            expands: isMultiline,
            textAlignVertical: isMultiline
                ? TextAlignVertical.top
                : TextAlignVertical.center,
            decoration: _decoration(context),
            controller: _controller,
            onChanged: widget.onChanged,
          );
        },
      ),
    );
  }
}
