import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'form_style.dart';

class IntTextbox extends StatefulWidget {
  const IntTextbox({
    super.key,
    this.initialValue,
    this.fillColor,
    required this.onChanged,
    this.outlineColor,
    required this.dataName,
    required this.width,
    required this.height,
  });

  final Color? fillColor;
  final Color? outlineColor;
  final String dataName;
  final ValueChanged<int> onChanged;
  final double width;
  final double height;
  final int? initialValue;

  @override
  State<IntTextbox> createState() => _IntTextboxState();
}

class _IntTextboxState extends State<IntTextbox> {
  final TextEditingController _controller = TextEditingController();
  late int _value = widget.initialValue ?? 0;

  @override
  void initState() {
    super.initState();
    _controller.text = _value.toString();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant IntTextbox oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialValue != widget.initialValue &&
        widget.initialValue != null) {
      _value = widget.initialValue!;
      _controller.text = _value.toString();
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
      child: TextField(
        cursorColor:
            widget.outlineColor ?? Theme.of(context).colorScheme.onSurface,
        style: Theme.of(context).textTheme.bodyMedium,
        textAlignVertical: TextAlignVertical.center,
        decoration: _decoration(context),
        controller: _controller,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        onChanged: (_) {
          setState(() {
            _value = int.tryParse(_controller.text) ?? 0;
            widget.onChanged(_value);
          });
        },
      ),
    );
  }
}
