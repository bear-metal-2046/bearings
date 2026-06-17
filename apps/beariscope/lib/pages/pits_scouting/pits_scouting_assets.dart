import 'package:beariscope/widgets/beariscope_card.dart';
import 'package:beariscope/models/pits_form_schema.dart';
import 'package:beariscope/models/pits_scouting_models.dart';
import 'package:beariscope/models/scouting_document.dart';
import 'package:beariscope/pages/pits_scouting/pits_scouting_widgets.dart';
import 'package:beariscope/providers/current_event_provider.dart';
import 'package:beariscope/providers/pits_form_schema_provider.dart';
import 'package:beariscope/providers/scouting_data_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:services/providers/api_provider.dart';
import 'package:services/providers/user_profile_provider.dart';

String? _pitsScouterName(ScoutingDocument? doc) {
  final scoutedBy = doc?.meta?['scoutedBy']?.toString().trim() ?? '';
  return scoutedBy.isNotEmpty ? scoutedBy : null;
}

class PitsScoutingTeamCard extends ConsumerWidget {
  final String teamName;
  final int teamNumber;
  final bool scouted;
  final ValueChanged<bool> onScoutedChanged;

  const PitsScoutingTeamCard({
    super.key,
    required this.teamName,
    required this.teamNumber,
    required this.scouted,
    required this.onScoutedChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ScoutingDocument? existingDoc;
    if (scouted) {
      final eventKey = ref.read(currentEventProvider);
      final allDocs = ref.read(scoutingDataProvider).asData?.value ?? [];
      final pitsDocs =
          allDocs
              .where(
                (doc) =>
                    doc.meta?['type'] == 'pits' &&
                    doc.meta?['event'] == eventKey &&
                    (doc.data['teamNumber'] as num?)?.toInt() == teamNumber,
              )
              .toList()
            ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
      existingDoc = pitsDocs.firstOrNull;
    }

    final scouterName = _pitsScouterName(existingDoc);

    return BeariscopeCard(
      title: teamName,
      subtitle: '$teamNumber',
      trailing: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            scouted ? 'Scouted' : 'Not Scouted',
            style: TextStyle(
              color: scouted ? Colors.green : Colors.red,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (scouterName != null)
            Text(
              'by $scouterName',
              style: TextStyle(
                color: scouted ? Colors.green : Colors.red,
                fontSize: 12,
              ),
            ),
        ],
      ),
      onTap: () async {
        final result = await Navigator.of(context, rootNavigator: true).push(
          MaterialPageRoute(
            builder: (context) => PitsScoutingFormPage(
              teamNumber: teamNumber,
              teamName: teamName,
              scouted: scouted,
              initialDoc: existingDoc,
            ),
          ),
        );

        if (result != null && result == true) {
          onScoutedChanged(true);
        }
      },
    );
  }
}

class PitsScoutingFormPage extends ConsumerStatefulWidget {
  final String teamName;
  final int teamNumber;
  final bool scouted;
  final ScoutingDocument? initialDoc;

  const PitsScoutingFormPage({
    super.key,
    required this.teamName,
    required this.teamNumber,
    required this.scouted,
    this.initialDoc,
  });

  @override
  ConsumerState<PitsScoutingFormPage> createState() =>
      _PitsScoutingFormPageState();
}

class _PitsScoutingFormPageState extends ConsumerState<PitsScoutingFormPage> {
  final Map<String, TextEditingController> _textControllers = {};
  final Map<String, String> _stringValues = {};
  final Map<String, Set<String>> _setValues = {};
  final Map<String, double> _numberValues = {};
  bool _initialized = false;

  static const Map<String, List<String>> _legacyStorageAliases = {
    'swerveGearRatio': ['swerveGR'],
    'shootingRange': ['rangeFromField'],
    'pathwayDetails': ['pathwayPreference'],
  };

  @override
  void dispose() {
    for (final controller in _textControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final schemaAsync = ref.watch(pitsFormSchemaProvider);
    final currentEventKey = ref.watch(currentEventProvider);
    final userInfo = ref.watch(userInfoProvider).asData?.value;
    final scoutedBy = userInfo?.name?.trim() ?? 'Unknown User';

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        appBar: AppBar(
          title: Text('Scouting ${widget.teamNumber}: ${widget.teamName}'),
        ),
        body: schemaAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) =>
              Center(child: Text('Failed to load form schema: $error')),
          data: (schema) {
            _initializeFromSchema(schema);

            return Center(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    ..._buildSectionWidgets(schema),
                    Padding(
                      padding: const EdgeInsets.all(30),
                      child: FilledButton(
                        onPressed: () async {
                          final submission = PitsScoutingSubmission(
                            teamName: widget.teamName,
                            teamNumber: widget.teamNumber,
                            hopperSize: _readIntField('hopperSize'),
                            motorType: _readStringField('motorType'),
                            drivetrainType: _readStringField('drivetrainType'),
                            swerveBrand: _readStringField('swerveBrand'),
                            swerveGearRatio: _readStringField(
                              'swerveGearRatio',
                            ),
                            wheelType: _readStringField('wheelType'),
                            chassisLength: _readDoubleField('chassisLength'),
                            chassisWidth: _readDoubleField('chassisWidth'),
                            chassisHeight: _readDoubleField('chassisHeight'),
                            horizontalExtensionLimit: _readDoubleField(
                              'horizontalExtensionLimit',
                            ),
                            verticalExtensionLimit: _readDoubleField(
                              'verticalExtensionLimit',
                            ),
                            weight: _readDoubleField('weight'),
                            climbMethod: _readStringField('climbMethod'),
                            climbLevel: _readSetField('climbLevel'),
                            climbConsistency: _readSliderField(
                              'climbConsistency',
                            ),
                            autoClimb: _readStringField('autoClimb'),
                            fuelCollectionLocation: _readSetField(
                              'fuelCollectionLocation',
                            ),
                            autoPaths: _readTextField('autoPaths'),
                            pathwayDetails: _readSetField('pathwayDetails'),
                            trenchCapability: _readStringField(
                              'trenchCapability',
                            ),
                            towerCapability: _readStringField(
                              'towerCapability',
                            ),
                            shooter: _readStringField('shooter'),
                            shooterNumber: _readIntField('shooterNumber'),
                            collectorType: _readStringField('collectorType'),
                            fuelOuttakeRate: _readDoubleField(
                              'fuelOuttakeRate',
                            ),
                            averageAccuracy: _readSliderField(
                              'averageAccuracy',
                            ),
                            moveWhileShooting: _readSetField(
                              'moveWhileShooting',
                            ),
                            shootingRange: _readSetField('shootingRange'),
                            indexerType: _readStringField('indexerType'),
                            notes: _readTextField('notes'),
                          );

                          final entry = submission.toIngestEntry(
                            eventKey: currentEventKey,
                            scoutedBy: scoutedBy,
                            existingId: widget.initialDoc?.id,
                          );

                          try {
                            await ref
                                .read(honeycombClientProvider)
                                .post(
                                  '/scout/ingest',
                                  data: {
                                    'entries': [entry],
                                  },
                                );
                            if (context.mounted) {
                              Navigator.pop(context, true);
                            }
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Failed to submit: $e')),
                              );
                            }
                          }
                        },
                        child: Text(
                          widget.scouted == false ? 'Submit' : 'Edit',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  void _initializeFromSchema(PitsFormSchema schema) {
    if (_initialized) {
      return;
    }

    final doc = widget.initialDoc?.data;

    for (final section in schema.sections) {
      for (final field in section.fields) {
        final rawValue = _readInitialRawValue(field, doc);

        switch (field.type) {
          case PitsFormFieldType.number ||
              PitsFormFieldType.text ||
              PitsFormFieldType.multilineText:
            final text = _normalizeTextValue(field, rawValue);
            _textControllers[field.id] = TextEditingController(text: text);

          case PitsFormFieldType.singleSelect || PitsFormFieldType.radio:
            _stringValues[field.id] =
                _normalizeStringSelection(field, rawValue) ?? '';

          case PitsFormFieldType.multiSelect:
            _setValues[field.id] = _normalizeSetSelection(field, rawValue);

          case PitsFormFieldType.slider:
            _numberValues[field.id] = _normalizeSliderValue(field, rawValue);
        }
      }
    }

    _initialized = true;
  }

  Object? _readInitialRawValue(PitsFormField field, Map<String, dynamic>? doc) {
    final keys = <String>{
      field.id,
      if (field.storageKey != null && field.storageKey!.isNotEmpty)
        field.storageKey!,
      ...?_legacyStorageAliases[field.id],
    };

    if (doc != null) {
      for (final key in keys) {
        if (doc.containsKey(key)) {
          return doc[key];
        }
      }
    }

    return field.defaultValue;
  }

  String _normalizeTextValue(PitsFormField field, Object? rawValue) {
    if (rawValue == null) {
      return '';
    }
    if (field.type == PitsFormFieldType.number && rawValue is num) {
      return _formatNumber(rawValue);
    }
    return rawValue.toString();
  }

  String? _normalizeStringSelection(PitsFormField field, Object? rawValue) {
    final asString = rawValue?.toString();
    if (asString != null && asString.isNotEmpty) {
      if (field.options.isEmpty || field.options.contains(asString)) {
        return asString;
      }
    }

    if (field.defaultValue is String) {
      final fallback = field.defaultValue as String;
      if (field.options.isEmpty || field.options.contains(fallback)) {
        return fallback;
      }
    }

    return field.options.firstOrNull;
  }

  Set<String> _normalizeSetSelection(PitsFormField field, Object? rawValue) {
    final candidates = switch (rawValue) {
      List() => rawValue.map((value) => value.toString()).toSet(),
      Set() => rawValue.map((value) => value.toString()).toSet(),
      String() => rawValue.trim().isEmpty ? <String>{} : {rawValue},
      _ => <String>{},
    };

    if (candidates.isEmpty) {
      return const <String>{};
    }

    if (field.options.isEmpty) {
      return candidates;
    }

    return candidates.where(field.options.contains).toSet();
  }

  double _normalizeSliderValue(PitsFormField field, Object? rawValue) {
    final min = _sliderMin(field);
    final max = _sliderMax(field);
    final fallback = _asDouble(field.defaultValue) ?? min;
    final value = _asDouble(rawValue) ?? fallback;
    return value.clamp(min, max).toDouble();
  }

  List<Widget> _buildSectionWidgets(PitsFormSchema schema) {
    final widgets = <Widget>[];

    for (final section in schema.sections) {
      widgets.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 30, 20, 0),
          child: Text(
            section.displayName,
            style: const TextStyle(fontSize: 25, fontFamily: 'Xolonium'),
          ),
        ),
      );

      for (final field in section.fields) {
        widgets.add(
          Padding(
            padding: _fieldPadding(field),
            child: _buildFieldWidget(field),
          ),
        );
      }
    }

    return widgets;
  }

  EdgeInsets _fieldPadding(PitsFormField field) {
    final horizontal = field.type == PitsFormFieldType.number ? 50.0 : 20.0;
    return EdgeInsets.symmetric(vertical: 10, horizontal: horizontal);
  }

  Widget _buildFieldWidget(PitsFormField field) {
    return switch (field.type) {
      PitsFormFieldType.number => NumberTextField(
        labelText: field.displayName,
        controller: _textControllers[field.id],
      ),
      PitsFormFieldType.singleSelect => DropdownButtonOneChoice(
        options: field.options,
        label: field.displayName,
        initialValue: _stringValues[field.id],
        onChanged: (value) {
          _stringValues[field.id] = value ?? _stringValues[field.id] ?? '';
        },
      ),
      PitsFormFieldType.multiSelect => MultipleChoice(
        options: field.options,
        label: field.displayName,
        initialSelection: _setValues[field.id]?.toList(),
        onSelectionChanged: (value) {
          _setValues[field.id] = value;
        },
      ),
      PitsFormFieldType.radio => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(field.displayName),
          RadioButton(
            options: field.options,
            initialValue: _stringValues[field.id],
            onChanged: (value) {
              _stringValues[field.id] = value ?? _stringValues[field.id] ?? '';
            },
          ),
        ],
      ),
      PitsFormFieldType.slider => SegmentedSlider(
        min: _sliderMin(field),
        max: _sliderMax(field),
        divisions: _sliderDivisions(field),
        label: field.displayName,
        initialValue: _numberValues[field.id],
        onChanged: (value) {
          _numberValues[field.id] = value;
        },
      ),
      PitsFormFieldType.text => TextField(
        controller: _textControllers[field.id],
        decoration: InputDecoration(labelText: field.displayName),
      ),
      PitsFormFieldType.multilineText => TextField(
        controller: _textControllers[field.id],
        keyboardType: TextInputType.multiline,
        maxLines: null,
        decoration: InputDecoration(labelText: field.displayName),
      ),
    };
  }

  double _sliderMin(PitsFormField field) => _asDouble(field.params['min']) ?? 0;

  double _sliderMax(PitsFormField field) {
    final min = _sliderMin(field);
    final max = _asDouble(field.params['max']) ?? (min + 1);
    return max > min ? max : min + 1;
  }

  int _sliderDivisions(PitsFormField field) {
    final min = _sliderMin(field);
    final max = _sliderMax(field);
    final fromSchema = field.params['divisions'];
    if (fromSchema is int && fromSchema > 0) {
      return fromSchema;
    }
    final range = (max - min).round();
    return range > 0 ? range : 1;
  }

  int? _readIntField(String fieldId) {
    final text = _textControllers[fieldId]?.text.trim() ?? '';
    return int.tryParse(text);
  }

  double? _readDoubleField(String fieldId) {
    final text = _textControllers[fieldId]?.text.trim() ?? '';
    return double.tryParse(text);
  }

  String _readStringField(String fieldId) => _stringValues[fieldId] ?? '';

  String _readTextField(String fieldId) =>
      _textControllers[fieldId]?.text ?? '';

  Set<String> _readSetField(String fieldId) => _setValues[fieldId] ?? {};

  double _readSliderField(String fieldId) => _numberValues[fieldId] ?? 0;

  double? _asDouble(Object? value) {
    if (value is num) {
      return value.toDouble();
    }
    if (value is String) {
      return double.tryParse(value);
    }
    return null;
  }

  String _formatNumber(num value) {
    final asDouble = value.toDouble();
    if (asDouble == asDouble.roundToDouble()) {
      return asDouble.toInt().toString();
    }
    return asDouble.toString();
  }
}
