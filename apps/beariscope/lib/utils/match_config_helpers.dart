import 'package:core/core.dart';

String? optionLabelForField({
  required MatchConfig config,
  required String sectionId,
  required String fieldId,
  required int index,
}) {
  PageConfig? page;
  for (final p in config.pages) {
    if (p.sectionId == sectionId) {
      page = p;
      break;
    }
  }
  if (page == null) return null;

  ComponentConfig? component;
  for (final c in page.components) {
    if (c.fieldId == fieldId) {
      component = c;
      break;
    }
  }
  if (component == null) return null;

  final options = component.parameters['options'];
  if (options is! List) return null;

  if (index < 0 || index >= options.length) return null;
  return options[index].toString();
}
