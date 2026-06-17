import 'dart:math';

import 'package:beariscope/models/match_field_ids.dart';
import 'package:beariscope/models/processed_scouting_doc.dart';
import 'package:beariscope/models/scouting_document.dart';
import 'package:beariscope/models/team_scouting_bundle.dart';
import 'package:beariscope/pages/export/export_options.dart';
import 'package:beariscope/pages/export/ui_creator_schema.dart';
import 'package:beariscope/pages/scout_audit/scout_audit_logic.dart';
import 'package:excel/excel.dart';

class ExportService {
  ExportService._();

  static const _stratRankingKeys = [
    'driverSkillRanking',
    'defensiveSkillRanking',
    'defensiveResilienceRanking',
    'mechanicalStabilityRanking',
  ];

  static const _stratRankingHeaders = [
    'Driver Skill Rank',
    'Def. Skill Rank',
    'Def. Resilience Rank',
    'Mech. Stability Rank',
  ];

  /// Builds a consolidated Excel workbook with multiple sheets based on options.
  static List<int> buildConsolidatedExcel({
    required List<ScoutingDocument> rawDocs,
    required List<ProcessedScoutingDoc> processedDocs,
    required UiCreatorSchema schema,
    required ExportOptions options,
    required String eventKey,
    Map<int, Map<String, ({int auto, int tele, List<int> teams})>>?
    tbaMatchData,
    ScoutAuditSnapshot? auditSnapshot,
  }) {
    final excel = Excel.createExcel();
    var isFirstSheet = true;

    if (options.sheets.rawMatch) {
      final sheetName = 'Raw Match Data';
      if (isFirstSheet) {
        excel.rename('Sheet1', sheetName);
        isFirstSheet = false;
      }
      _buildMatchSheet(
        excel: excel,
        sheetName: sheetName,
        docs: rawDocs,
        processedDocs: null,
        schema: schema,
        options: options,
        eventKey: eventKey,
        tbaMatchData: tbaMatchData,
        applyScalars: false,
      );
    }

    if (options.sheets.processedMatch) {
      final sheetName = 'Processed Match Data';
      if (isFirstSheet) {
        excel.rename('Sheet1', sheetName);
        isFirstSheet = false;
      }
      _buildMatchSheet(
        excel: excel,
        sheetName: sheetName,
        docs: rawDocs,
        processedDocs: processedDocs,
        schema: schema,
        options: options,
        eventKey: eventKey,
        tbaMatchData: tbaMatchData,
        applyScalars: true,
      );
    }

    if (options.sheets.stratRaw) {
      final sheetName = 'Strat Raw';
      if (isFirstSheet) {
        excel.rename('Sheet1', sheetName);
        isFirstSheet = false;
      }
      _buildStratRawSheet(
        excel: excel,
        sheetName: sheetName,
        docs: rawDocs,
        options: options,
        eventKey: eventKey,
      );
    }

    if (options.sheets.stratZScore) {
      final sheetName = 'Strat Z-Score';
      if (isFirstSheet) {
        excel.rename('Sheet1', sheetName);
        isFirstSheet = false;
      }
      _buildStratZScoreSheet(
        excel: excel,
        sheetName: sheetName,
        docs: rawDocs,
        options: options,
        eventKey: eventKey,
      );
    }

    if (options.sheets.correctionTodoList && auditSnapshot != null) {
      final sheetName = 'Correction To-Do List';
      if (isFirstSheet) {
        excel.rename('Sheet1', sheetName);
        isFirstSheet = false;
      }
      _buildCorrectionTodoSheet(
        excel: excel,
        sheetName: sheetName,
        snapshot: auditSnapshot,
      );
    }

    // Remove default sheet if nothing was added
    if (isFirstSheet) {
      excel.delete('Sheet1');
    }

    final encoded = excel.encode();
    if (encoded == null) throw StateError('Excel encoding returned null');
    return encoded;
  }

  /// Fields that should have scalars applied when exporting processed data.
  static const _scaledAutoFields = {kAutoFuelScored, kAutoFuelPassed};
  static const _scaledTeleFields = {
    kTeleFuelScored,
    kTeleFuelPassed,
    kTeleFuelPoached,
  };

  static void _buildMatchSheet({
    required Excel excel,
    required String sheetName,
    required List<ScoutingDocument> docs,
    required List<ProcessedScoutingDoc>? processedDocs,
    required UiCreatorSchema schema,
    required ExportOptions options,
    required String eventKey,
    Map<int, Map<String, ({int auto, int tele, List<int> teams})>>?
    tbaMatchData,
    required bool applyScalars,
  }) {
    // Build a lookup map for processed docs by id
    final processedById = <String, ProcessedScoutingDoc>{};
    if (processedDocs != null) {
      for (final doc in processedDocs) {
        processedById[doc.raw.id] = doc;
      }
    }

    final filtered =
        docs.where((doc) {
          if (doc.meta?['type']?.toString() != 'match') return false;
          if (doc.meta?['event']?.toString() != eventKey) return false;
          final matchNum = TeamScoutingBundle.matchNumber(doc);
          final teamNum = TeamScoutingBundle.teamNumber(doc);
          if (options.matchFrom != null &&
              matchNum != null &&
              matchNum < options.matchFrom!) {
            return false;
          }
          if (options.matchTo != null &&
              matchNum != null &&
              matchNum > options.matchTo!) {
            return false;
          }
          if (options.teamFilter != null &&
              options.teamFilter!.isNotEmpty &&
              !options.teamFilter!.contains(teamNum)) {
            return false;
          }
          return true;
        }).toList()..sort((a, b) {
          final matchA = TeamScoutingBundle.matchNumber(a) ?? 0;
          final matchB = TeamScoutingBundle.matchNumber(b) ?? 0;
          if (matchA != matchB) return matchA.compareTo(matchB);
          final teamA = TeamScoutingBundle.teamNumber(a) ?? 0;
          final teamB = TeamScoutingBundle.teamNumber(b) ?? 0;
          final allianceA = _allianceFromTba(matchA, teamA, tbaMatchData);
          final allianceB = _allianceFromTba(matchB, teamB, tbaMatchData);
          final allianceCmp = _compareAlliance(allianceA, allianceB);
          if (allianceCmp != 0) return allianceCmp;
          return teamA.compareTo(teamB);
        });

    // Calculate alliance sums for color coding
    Map<String, ({int auto, int tele})> allianceSums = {};
    if (options.colorCodeAccuracy && tbaMatchData != null) {
      final allEventDocs = docs.where(
        (doc) =>
            doc.meta?['type']?.toString() == 'match' &&
            doc.meta?['event']?.toString() == eventKey,
      );
      for (final doc in allEventDocs) {
        final matchNum = TeamScoutingBundle.matchNumber(doc);
        final teamNum = TeamScoutingBundle.teamNumber(doc);
        if (matchNum == null || teamNum == null) continue;
        final alliance = _allianceFromTba(matchNum, teamNum, tbaMatchData);
        if (alliance == null) continue;
        final key = '${matchNum}_$alliance';
        final prev = allianceSums[key] ?? (auto: 0, tele: 0);
        allianceSums[key] = (
          auto:
              prev.auto +
              _toInt(
                TeamScoutingBundle.getMatchField(doc, 'auto', 'fuel_scored'),
              ),
          tele:
              prev.tele +
              _toInt(
                TeamScoutingBundle.getMatchField(doc, 'tele', 'fuel_scored'),
              ),
        );
      }
    }

    final schemaColumns = options.includeNotes
        ? schema.columns
        : schema.columns.where((c) => !c.isNotesField).toList();

    const fixedCols = 3;
    int? autoFuelColIdx;
    int? teleFuelColIdx;
    for (var i = 0; i < schemaColumns.length; i++) {
      if (schemaColumns[i].isAutoFuelScored && autoFuelColIdx == null) {
        autoFuelColIdx = fixedCols + i;
      }
      if (schemaColumns[i].isTeleFuelScored && teleFuelColIdx == null) {
        teleFuelColIdx = fixedCols + i;
      }
    }

    final sheet = excel[sheetName];
    final headerStyle = CellStyle(
      bold: true,
      backgroundColorHex: ExcelColor.fromHexString('#DBEAFE'),
    );

    // Add "Scaled" indicator column for processed data
    final headers = [
      'Team #',
      'Match #',
      'Scouter',
      ...schemaColumns.map((c) => c.columnHeader),
      if (applyScalars) 'Scaled',
    ];
    for (var col = 0; col < headers.length; col++) {
      final cell = sheet.cell(
        CellIndex.indexByColumnRow(columnIndex: col, rowIndex: 0),
      );
      cell.value = TextCellValue(headers[col]);
      cell.cellStyle = headerStyle;
    }

    for (var rowIdx = 0; rowIdx < filtered.length; rowIdx++) {
      final doc = filtered[rowIdx];
      final processed = processedById[doc.id];
      final teamNum = TeamScoutingBundle.teamNumber(doc);
      final matchNum = TeamScoutingBundle.matchNumber(doc);
      final alliance = (matchNum != null && teamNum != null)
          ? _allianceFromTba(matchNum, teamNum, tbaMatchData)
          : null;
      final row = rowIdx + 1;

      void writeCell(int col, CellValue value, {ExcelColor? bgColor}) {
        final cell = sheet.cell(
          CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row),
        );
        cell.value = value;
        if (bgColor != null) {
          cell.cellStyle = CellStyle(backgroundColorHex: bgColor);
        }
      }

      writeCell(
        0,
        teamNum != null ? IntCellValue(teamNum) : TextCellValue(''),
        bgColor: _allianceFill(alliance),
      );
      writeCell(
        1,
        matchNum != null ? IntCellValue(matchNum) : TextCellValue(''),
      );
      writeCell(
        2,
        options.anonymizeScouters
            ? TextCellValue('')
            : TextCellValue(doc.meta?['scoutedBy']?.toString() ?? ''),
      );

      for (var i = 0; i < schemaColumns.length; i++) {
        final column = schemaColumns[i];
        final raw = TeamScoutingBundle.getMatchField(
          doc,
          column.sectionId,
          column.fieldId,
        );

        // Apply scalar if this is a scaled field and we have processed data
        num? scaledValue;
        if (applyScalars && processed != null && raw is num) {
          final scalar = _getScalarForField(
            processed,
            column.sectionId,
            column.fieldId,
            options.correctionThresholds,
          );
          if (scalar != 1.0) {
            scaledValue = raw * scalar;
          }
        }

        final value = scaledValue != null
            ? DoubleCellValue(
                double.parse(scaledValue.toDouble().toStringAsFixed(2)),
              )
            : _toCellValue(raw);

        ExcelColor? bgColor;

        if (options.colorCodeAccuracy &&
            tbaMatchData != null &&
            matchNum != null &&
            alliance != null &&
            (fixedCols + i == autoFuelColIdx ||
                fixedCols + i == teleFuelColIdx)) {
          final tba = tbaMatchData[matchNum]?[alliance];
          if (tba != null) {
            final sums = allianceSums['${matchNum}_$alliance'];
            if (sums != null) {
              final truth = fixedCols + i == autoFuelColIdx
                  ? tba.auto
                  : tba.tele;
              final scouted = fixedCols + i == autoFuelColIdx
                  ? sums.auto
                  : sums.tele;
              bgColor = _accuracyColor(scouted, truth, options.colorThresholds);
            }
          }
        }

        writeCell(fixedCols + i, value, bgColor: bgColor);
      }

      // Add scaled indicator for processed data
      if (applyScalars) {
        final isScaled = processed?.isScaled ?? false;
        writeCell(
          fixedCols + schemaColumns.length,
          TextCellValue(isScaled ? 'Yes' : 'No'),
        );
      }
    }
  }

  static double _getScalarForField(
    ProcessedScoutingDoc doc,
    String sectionId,
    String fieldId,
    CorrectionThresholds thresholds,
  ) {
    double rawScalar = 1.0;

    if (sectionId == kSectionAuto && _scaledAutoFields.contains(fieldId)) {
      rawScalar = doc.autoFuelScalar;
    } else if (sectionId == kSectionTele &&
        _scaledTeleFields.contains(fieldId)) {
      rawScalar = doc.teleFuelScalar;
    }

    // Check if deviation exceeds minimum threshold
    final deviation = (rawScalar - 1.0).abs();
    if (deviation < thresholds.minDeviation) {
      return 1.0; // Don't apply correction for small deviations
    }

    // Cap the scalar at maxScalar
    if (rawScalar > thresholds.maxScalar) {
      return thresholds.maxScalar;
    }
    if (rawScalar < 1.0 / thresholds.maxScalar) {
      return 1.0 / thresholds.maxScalar;
    }

    return rawScalar;
  }

  static void _buildStratRawSheet({
    required Excel excel,
    required String sheetName,
    required List<ScoutingDocument> docs,
    required ExportOptions options,
    required String eventKey,
  }) {
    final stratDocs =
        docs.where((doc) {
          if (doc.meta?['type']?.toString() != 'strat') return false;
          if (doc.meta?['event']?.toString() != eventKey) return false;
          final mn = _matchNumber(doc);
          if (options.matchFrom != null &&
              mn != null &&
              mn < options.matchFrom!) {
            return false;
          }
          if (options.matchTo != null && mn != null && mn > options.matchTo!) {
            return false;
          }
          return true;
        }).toList()..sort((a, b) {
          final matchA = _matchNumber(a) ?? 0;
          final matchB = _matchNumber(b) ?? 0;
          if (matchA != matchB) return matchA.compareTo(matchB);
          return _compareAlliance(
            a.meta?['alliance']?.toString(),
            b.meta?['alliance']?.toString(),
          );
        });

    final sheet = excel[sheetName];
    final headerStyle = CellStyle(
      bold: true,
      backgroundColorHex: ExcelColor.fromHexString('#DBEAFE'),
    );

    const headers = [
      'Team #',
      'Match #',
      'Alliance',
      'Scouter',
      ..._stratRankingHeaders,
      'Human Player Score',
    ];
    for (var col = 0; col < headers.length; col++) {
      final cell = sheet.cell(
        CellIndex.indexByColumnRow(columnIndex: col, rowIndex: 0),
      );
      cell.value = TextCellValue(headers[col]);
      cell.cellStyle = headerStyle;
    }

    var row = 1;
    for (final doc in stratDocs) {
      final matchNum = _matchNumber(doc);
      final alliance = doc.meta?['alliance']?.toString();
      final scoutedBy = options.anonymizeScouters
          ? ''
          : doc.meta?['scoutedBy']?.toString() ?? '';
      final teamIds = _stratTeams(doc);
      final teamCellColor = _allianceFill(alliance);
      final ranks = <String, Map<int, int>>{
        for (final key in _stratRankingKeys) key: _rankMap(doc, key),
      };
      final allTeams = <int>{...teamIds};
      for (final key in _stratRankingKeys) {
        allTeams.addAll(ranks[key]!.keys);
      }

      for (final teamNum in allTeams.toList()..sort()) {
        if (options.teamFilter != null &&
            options.teamFilter!.isNotEmpty &&
            !options.teamFilter!.contains(teamNum)) {
          continue;
        }

        void writeCell(int col, CellValue value, {ExcelColor? bgColor}) {
          final cell = sheet.cell(
            CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row),
          );
          cell.value = value;
          if (bgColor != null) {
            cell.cellStyle = CellStyle(backgroundColorHex: bgColor);
          }
        }

        writeCell(0, IntCellValue(teamNum), bgColor: teamCellColor);
        writeCell(
          1,
          matchNum != null ? IntCellValue(matchNum) : TextCellValue(''),
        );
        writeCell(2, TextCellValue(alliance ?? ''));
        writeCell(3, TextCellValue(scoutedBy));

        for (var i = 0; i < _stratRankingKeys.length; i++) {
          final rank = ranks[_stratRankingKeys[i]]![teamNum];
          writeCell(
            4 + i,
            rank != null ? IntCellValue(rank) : TextCellValue(''),
          );
        }

        writeCell(8, _toCellValue(_humanPlayerScore(doc.data)));
        row++;
      }
    }
  }

  static void _buildStratZScoreSheet({
    required Excel excel,
    required String sheetName,
    required List<ScoutingDocument> docs,
    required ExportOptions options,
    required String eventKey,
  }) {
    final stratDocs = docs.where((doc) {
      if (doc.meta?['type']?.toString() != 'strat') return false;
      if (doc.meta?['event']?.toString() != eventKey) return false;
      final mn = _matchNumber(doc);
      if (options.matchFrom != null && mn != null && mn < options.matchFrom!) {
        return false;
      }
      if (options.matchTo != null && mn != null && mn > options.matchTo!) {
        return false;
      }
      return true;
    }).toList();

    final rawScores = <String, Map<int, List<double>>>{
      for (final key in _stratRankingKeys) key: {},
    };
    for (final doc in stratDocs) {
      for (final key in _stratRankingKeys) {
        final list = doc.data[key];
        if (list is! List) continue;
        final n = list.length;
        for (var i = 0; i < n; i++) {
          final team = int.tryParse(list[i]?.toString() ?? '');
          if (team == null) continue;
          rawScores[key]!.putIfAbsent(team, () => []).add((n - i).toDouble());
        }
      }
    }

    Map<int, double> zFor(String key) {
      final perTeam = rawScores[key]!;
      if (perTeam.isEmpty) return {};
      final averages = perTeam.map(
        (team, scores) =>
            MapEntry(team, scores.fold(0.0, (a, b) => a + b) / scores.length),
      );
      return _zScoreMap(averages);
    }

    final allTeams = rawScores.values.expand((m) => m.keys).toSet().toList()
      ..sort();
    final teams = options.teamFilter != null && options.teamFilter!.isNotEmpty
        ? allTeams.where((t) => options.teamFilter!.contains(t)).toList()
        : allTeams;
    final zMaps = _stratRankingKeys.map(zFor).toList();

    final sheet = excel[sheetName];
    final headerStyle = CellStyle(
      bold: true,
      backgroundColorHex: ExcelColor.fromHexString('#DBEAFE'),
    );
    const headers = [
      'Team #',
      'Driver Skill Z',
      'Def. Skill Z',
      'Def. Resilience Z',
      'Mech. Stability Z',
    ];
    for (var col = 0; col < headers.length; col++) {
      final cell = sheet.cell(
        CellIndex.indexByColumnRow(columnIndex: col, rowIndex: 0),
      );
      cell.value = TextCellValue(headers[col]);
      cell.cellStyle = headerStyle;
    }

    for (var rowIdx = 0; rowIdx < teams.length; rowIdx++) {
      final team = teams[rowIdx];
      final row = rowIdx + 1;
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row))
          .value = IntCellValue(
        team,
      );
      for (var i = 0; i < zMaps.length; i++) {
        final z = zMaps[i][team];
        sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: i + 1, rowIndex: row))
            .value = z != null
            ? DoubleCellValue(double.parse(z.toStringAsFixed(8)))
            : TextCellValue('');
      }
    }
  }

  static void _buildCorrectionTodoSheet({
    required Excel excel,
    required String sheetName,
    required ScoutAuditSnapshot snapshot,
  }) {
    final sheet = excel[sheetName];
    final headerStyle = CellStyle(
      bold: true,
      backgroundColorHex: ExcelColor.fromHexString('#DBEAFE'),
    );

    const headers = [
      'Match #',
      'Type',
      'Team(s) / Alliance',
      'Details',
      'Claimed By',
      'Done?',
    ];

    for (var col = 0; col < headers.length; col++) {
      final cell = sheet.cell(
        CellIndex.indexByColumnRow(columnIndex: col, rowIndex: 0),
      );
      cell.value = TextCellValue(headers[col]);
      cell.cellStyle = headerStyle;
    }

    final rows =
        <({int matchNumber, String type, String teams, String details})>[];

    for (final issue in snapshot.incorrect) {
      rows.add((
        matchNumber: issue.matchNumber,
        type: 'Incorrect',
        teams:
            '${issue.teams.join(', ')} (${issue.alliance == 'red' ? 'Red' : 'Blue'})',
        details: '${(issue.deviation * 100).toStringAsFixed(0)}% off TBA',
      ));
    }

    for (final issue in snapshot.incompleteMatches) {
      final missing = issue.missingSlots.map((slot) => slot.label).join(', ');
      rows.add((
        matchNumber: issue.matchNumber,
        type: issue.entryType == ScoutAuditEntryType.strat
            ? 'Incomplete (Strat)'
            : 'Incomplete',
        teams: '$missing missing',
        details:
            '${issue.scoutedCount}/${issue.expectedCount} ${issue.entryType == ScoutAuditEntryType.strat ? 'alliances' : 'scouted'}',
      ));
    }

    for (final issue in snapshot.notInTba) {
      rows.add((
        matchNumber: issue.matchNumber,
        type: issue.entryType == ScoutAuditEntryType.strat
            ? 'Not in TBA (Strat)'
            : 'Not in TBA',
        teams: issue.entryType == ScoutAuditEntryType.strat
            ? 'Strat · ${_allianceLabel(issue.alliance)}'
            : issue.teamNumber == null
            ? issue.positionLabel
            : '${issue.teamNumber} · ${issue.positionLabel}',
        details: '—',
      ));
    }

    for (final issue in snapshot.duplicates) {
      rows.add((
        matchNumber: issue.matchNumber,
        type: issue.entryType == ScoutAuditEntryType.strat
            ? 'Duplicate (Strat)'
            : 'Duplicate',
        teams: issue.entryType == ScoutAuditEntryType.strat
            ? 'Strat · ${_allianceLabel(issue.alliance)}'
            : issue.teamNumber == null
            ? _posLabel(issue.pos)
            : '${issue.teamNumber} · ${_posLabel(issue.pos)}',
        details: '${issue.entries.length} entries',
      ));
    }

    rows.sort((a, b) {
      final byMatch = a.matchNumber.compareTo(b.matchNumber);
      if (byMatch != 0) return byMatch;
      return a.type.compareTo(b.type);
    });

    for (var i = 0; i < rows.length; i++) {
      final row = rows[i];
      final rowIndex = i + 1;

      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: rowIndex))
          .value = IntCellValue(
        row.matchNumber,
      );
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: rowIndex))
          .value = TextCellValue(
        row.type,
      );
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: rowIndex))
          .value = TextCellValue(
        row.teams,
      );
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: rowIndex))
          .value = TextCellValue(
        row.details,
      );
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: rowIndex))
          .value = TextCellValue(
        '',
      );
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: rowIndex))
          .value = TextCellValue(
        'FALSE',
      );
    }
  }

  // Legacy methods for backward compatibility
  static List<int> buildExcel({
    required List<ScoutingDocument> docs,
    required UiCreatorSchema schema,
    required ExportOptions options,
    required String eventKey,
    Map<int, Map<String, ({int auto, int tele, List<int> teams})>>?
    tbaMatchData,
  }) {
    return buildConsolidatedExcel(
      rawDocs: docs,
      processedDocs: [],
      schema: schema,
      options: options.copyWith(sheets: const ExportSheets(rawMatch: true)),
      eventKey: eventKey,
      tbaMatchData: tbaMatchData,
    );
  }

  static List<int> buildStratRawExcel({
    required List<ScoutingDocument> docs,
    required ExportOptions options,
    required String eventKey,
  }) {
    final excel = Excel.createExcel();
    excel.rename('Sheet1', 'Strat Raw');
    _buildStratRawSheet(
      excel: excel,
      sheetName: 'Strat Raw',
      docs: docs,
      options: options,
      eventKey: eventKey,
    );
    final encoded = excel.encode();
    if (encoded == null) throw StateError('Excel encoding returned null');
    return encoded;
  }

  static List<int> buildStratZScoreExcel({
    required List<ScoutingDocument> docs,
    required ExportOptions options,
    required String eventKey,
  }) {
    final excel = Excel.createExcel();
    excel.rename('Sheet1', 'Strat Z-Score');
    _buildStratZScoreSheet(
      excel: excel,
      sheetName: 'Strat Z-Score',
      docs: docs,
      options: options,
      eventKey: eventKey,
    );
    final encoded = excel.encode();
    if (encoded == null) throw StateError('Excel encoding returned null');
    return encoded;
  }

  /// Preview counts for the export summary.
  static ({int match, int stratRaw, int stratZScore, int correctionTodo})
  previewCounts(
    List<ScoutingDocument> docs,
    ExportOptions options,
    String eventKey,
  ) {
    return (
      match: previewCount(docs, options, eventKey),
      stratRaw: previewStratRawCount(docs, options, eventKey),
      stratZScore: previewStratZScoreCount(docs, options, eventKey),
      correctionTodo: options.sheets.correctionTodoList ? 1 : 0,
    );
  }

  static int previewCount(
    List<ScoutingDocument> docs,
    ExportOptions options,
    String eventKey,
  ) {
    return docs.where((doc) {
      if (doc.meta?['type']?.toString() != 'match') return false;
      if (doc.meta?['event']?.toString() != eventKey) return false;
      final matchNum = TeamScoutingBundle.matchNumber(doc);
      final teamNum = TeamScoutingBundle.teamNumber(doc);
      if (options.matchFrom != null &&
          matchNum != null &&
          matchNum < options.matchFrom!) {
        return false;
      }
      if (options.matchTo != null &&
          matchNum != null &&
          matchNum > options.matchTo!) {
        return false;
      }
      if (options.teamFilter != null &&
          options.teamFilter!.isNotEmpty &&
          !options.teamFilter!.contains(teamNum)) {
        return false;
      }
      return true;
    }).length;
  }

  static int previewStratRawCount(
    List<ScoutingDocument> docs,
    ExportOptions options,
    String eventKey,
  ) {
    var count = 0;
    for (final doc in docs) {
      if (doc.meta?['type']?.toString() != 'strat') continue;
      if (doc.meta?['event']?.toString() != eventKey) continue;
      final mn = _matchNumber(doc);
      if (options.matchFrom != null && mn != null && mn < options.matchFrom!) {
        continue;
      }
      if (options.matchTo != null && mn != null && mn > options.matchTo!) {
        continue;
      }
      final teams = _stratTeams(doc);
      if (options.teamFilter != null && options.teamFilter!.isNotEmpty) {
        count += teams
            .where((team) => options.teamFilter!.contains(team))
            .length;
      } else {
        count += teams.length;
      }
    }
    return count;
  }

  static int previewStratZScoreCount(
    List<ScoutingDocument> docs,
    ExportOptions options,
    String eventKey,
  ) {
    final teams = <int>{};
    for (final doc in docs) {
      if (doc.meta?['type']?.toString() != 'strat') continue;
      if (doc.meta?['event']?.toString() != eventKey) continue;
      final mn = _matchNumber(doc);
      if (options.matchFrom != null && mn != null && mn < options.matchFrom!) {
        continue;
      }
      if (options.matchTo != null && mn != null && mn > options.matchTo!) {
        continue;
      }
      teams.addAll(_stratTeams(doc));
    }
    if (options.teamFilter != null && options.teamFilter!.isNotEmpty) {
      return teams.where((t) => options.teamFilter!.contains(t)).length;
    }
    return teams.length;
  }

  static int _compareAlliance(String? a, String? b) {
    final order = {'red': 0, 'blue': 1};
    final oa = order[a?.toLowerCase() ?? ''];
    final ob = order[b?.toLowerCase() ?? ''];
    if (oa != null && ob != null) return oa.compareTo(ob);
    if (oa != null) return -1;
    if (ob != null) return 1;
    return 0;
  }

  static int? _matchNumber(ScoutingDocument doc) {
    return TeamScoutingBundle.matchNumber(doc);
  }

  static String? _allianceFromTba(
    int matchNum,
    int teamNum,
    Map<int, Map<String, ({int auto, int tele, List<int> teams})>>?
    tbaMatchData,
  ) {
    final matchEntry = tbaMatchData?[matchNum];
    if (matchEntry == null) return null;
    for (final entry in matchEntry.entries) {
      if (entry.value.teams.contains(teamNum)) return entry.key;
    }
    return null;
  }

  static ExcelColor? _allianceFill(String? alliance) {
    switch (alliance?.toLowerCase()) {
      case 'red':
        return ExcelColor.fromHexString('#FECACA');
      case 'blue':
        return ExcelColor.fromHexString('#BFDBFE');
      default:
        return null;
    }
  }

  static Map<int, int> _rankMap(ScoutingDocument doc, String key) {
    final list = doc.data[key];
    final result = <int, int>{};
    if (list is! List) return result;
    for (var i = 0; i < list.length; i++) {
      final team = int.tryParse(list[i]?.toString() ?? '');
      if (team != null) result[team] = i + 1;
    }
    return result;
  }

  static List<int> _stratTeams(ScoutingDocument doc) {
    final teams = <int>{};
    for (final key in _stratRankingKeys) {
      final list = doc.data[key];
      if (list is! List) continue;
      for (final entry in list) {
        final team = int.tryParse(entry?.toString() ?? '');
        if (team != null) teams.add(team);
      }
    }
    return teams.toList();
  }

  static double? _humanPlayerScore(Map<String, dynamic> data) {
    final auto = data['autoHumanPlayerScore'];
    final tele = data['teleHumanPlayerScore'];
    if (auto is num || tele is num) {
      return (auto is num ? auto.toDouble() : 0.0) +
          (tele is num ? tele.toDouble() : 0.0);
    }
    final legacy = data['humanPlayerScore'];
    if (legacy is num) return legacy.toDouble();
    return null;
  }

  static Map<int, double> _zScoreMap(Map<int, double> averages) {
    if (averages.isEmpty) return {};
    final values = averages.values.toList();
    final mean = values.fold(0.0, (a, b) => a + b) / values.length;
    final variance =
        values.fold(0.0, (a, b) => a + pow(b - mean, 2)) / values.length;
    final sd = sqrt(variance);
    return averages.map((team, avg) {
      if (sd == 0 || sd.isNaN || sd.isInfinite) {
        return MapEntry(team, 0.0);
      }
      final z = (avg - mean) / sd;
      return MapEntry(team, (z.isNaN || z.isInfinite) ? 0.0 : z);
    });
  }

  static CellValue _toCellValue(dynamic raw) {
    if (raw == null) return TextCellValue('');
    if (raw is bool) return TextCellValue(raw ? 'Yes' : 'No');
    if (raw is int) return IntCellValue(raw);
    if (raw is double) return DoubleCellValue(raw);
    if (raw is List) {
      return TextCellValue(raw.map((e) => e.toString()).join(', '));
    }
    return TextCellValue(raw.toString());
  }

  static int _toInt(dynamic raw) {
    if (raw is int) return raw;
    if (raw is double) return raw.toInt();
    if (raw is num) return raw.toInt();
    return 0;
  }

  static ExcelColor? _accuracyColor(
    int scouted,
    int truth,
    ColorThresholds thresholds,
  ) {
    if (truth <= 0) return null;
    final deviation = (scouted - truth).abs() / truth;
    if (deviation < thresholds.good) return null;
    if (deviation < thresholds.warning) {
      return ExcelColor.fromHexString('#FEF08A'); // Yellow
    }
    if (deviation < thresholds.bad) {
      return ExcelColor.fromHexString('#FED7AA'); // Orange
    }
    return ExcelColor.fromHexString('#FECACA'); // Red
  }

  static String _posLabel(int? pos) {
    return switch (pos) {
      0 => 'Red 1',
      1 => 'Red 2',
      2 => 'Red 3',
      3 => 'Blue 1',
      4 => 'Blue 2',
      5 => 'Blue 3',
      _ => 'Unknown Position',
    };
  }

  static String _allianceLabel(String? alliance) {
    return switch (alliance) {
      'red' => 'Red Alliance',
      'blue' => 'Blue Alliance',
      _ => 'Unknown Alliance',
    };
  }
}
