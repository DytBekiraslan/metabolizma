import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/persentil_calculator.dart';
import '../services/persentil_data.dart';
import '../widgets/flippable_card.dart';
import 'growth_chart_screen.dart';

class GrowthAssessmentScreen extends StatefulWidget {
  final PatientRecord initialRecord;

  const GrowthAssessmentScreen({
    Key? key,
    required this.initialRecord,
  }) : super(key: key);

  @override
  State<GrowthAssessmentScreen> createState() => _GrowthAssessmentScreenState();
}

class _GrowthAssessmentScreenState extends State<GrowthAssessmentScreen> {
  final PersentilCalculator _persentilCalculator = PersentilCalculator();
  PercentileCalculationResult? _percentileResult;

  @override
  void initState() {
    super.initState();
    print(
        'DEBUG GrowthAssessmentScreen initState: initialRecord.selectedGender = ${widget.initialRecord.selectedGender}');
    print(
        'DEBUG GrowthAssessmentScreen initState: initialRecord.patientName = ${widget.initialRecord.patientName}');
    print(
        'DEBUG GrowthAssessmentScreen initState: initialRecord.weight = ${widget.initialRecord.weight}');
    print(
        'DEBUG GrowthAssessmentScreen initState: initialRecord.height = ${widget.initialRecord.height}');
    _percentileResult = _computePercentiles();
  }

  PercentileCalculationResult? _computePercentiles() {
    final record = widget.initialRecord;
    if (record.weight <= 0 ||
        record.height <= 0 ||
        record.chronologicalAgeInMonths <= 0) {
      return null;
    }

    try {
      return _persentilCalculator.calculateAllPercentiles(
        chronologicalAgeInMonths: record.chronologicalAgeInMonths,
        gender: record.selectedGender,
        weight: record.weight,
        height: record.height,
      );
    } catch (error, stackTrace) {
      debugPrint('GrowthAssessmentScreen percentile calc error: $error');
      debugPrintStack(stackTrace: stackTrace);
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Büyüme ve Gelişme Değerlendirmesi'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildPatientInfoCard(widget.initialRecord),
            const SizedBox(height: 20),
            _buildGrowthAssessmentSection(context, widget.initialRecord),
          ],
        ),
      ),
    );
  }

  Widget _buildPatientInfoCard(PatientRecord record) {
    final isMale = record.selectedGender == 'Erkek';
    final genderColor = isMale ? Colors.blue : Colors.pink;

    double bmi = 0;
    if (record.height > 0 && record.weight > 0) {
      double heightInMeters = record.height / 100.0;
      bmi = record.weight / (heightInMeters * heightInMeters);
    }

    return Card(
      elevation: 4,
      color: genderColor.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              record.patientName,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildInfoBox(
                    'Yaş',
                    '${record.chronologicalAgeYears} yıl ${record.chronologicalAgeMonths} ay',
                    Icons.cake),
                _buildInfoBox(
                    'Cinsiyet',
                    record.selectedGender == 'Erkek' ? 'Erkek' : 'Kız',
                    Icons.person),
                _buildInfoBox('Boy', '${record.height.toStringAsFixed(1)} cm',
                    Icons.height),
                _buildInfoBox(
                    'Ağırlık',
                    '${record.weight.toStringAsFixed(1)} kg',
                    Icons.monitor_weight),
                _buildInfoBox('BKİ', bmi > 0 ? bmi.toStringAsFixed(1) : '-',
                    Icons.analytics),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoBox(String label, String value, IconData icon) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, color: Colors.blue.shade700),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildGrowthAssessmentSection(
      BuildContext context, PatientRecord record) {
    final percentileResult = _percentileResult;
    final bool canFlipCards = percentileResult?.hasHeightAge ?? false;
    final bool overWhoWeightLimit = record.chronologicalAgeInMonths > 120;
    final chronoText = _formatChronologicalAge(record, includeMonthTotal: true);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Büyüme ve Gelişme Değerlendirmesi',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(
          'Kronolojik Yaş: $chronoText',
          style: const TextStyle(
              fontSize: 13, fontWeight: FontWeight.w500, color: Colors.black54),
        ),
        if (percentileResult == null) ...[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.orange.shade200),
            ),
            child: const Text(
              'Kayıtta boy ve ağırlık bilgileri eksik ya da hatalı olduğu için persentiller tekrar hesaplanamadı. Kaydedilen değerler gösterilmektedir.',
              style: TextStyle(fontSize: 12, color: Colors.black87),
            ),
          ),
        ],
        const SizedBox(height: 12),

        // Ağırlık Persentili
        Row(
          children: [
            Expanded(
              child: canFlipCards && percentileResult != null
                  ? FlippableCard(
                      frontChild: _buildDisplayBoxWithBorder(
                        context,
                        'Ağırlık Persentili\nNEYZİ (Kronolojik)',
                        percentileResult.neyziWeightPercentileChronoAge,
                        Colors.orange,
                        record: record,
                        percentileResult: percentileResult,
                      ),
                      backChild: _buildDisplayBoxWithBorder(
                        context,
                        'Ağırlık Persentili\nNEYZİ (Boy Yaşı)',
                        percentileResult.neyziWeightPercentileHeightAge,
                        Colors.orange,
                        record: record,
                        percentileResult: percentileResult,
                        useHeightAgeForPercentiles: true,
                      ),
                    )
                  : _buildDisplayBoxWithBorder(
                      context,
                      'Ağırlık Persentili\nNEYZİ',
                      percentileResult?.neyziWeightPercentileChronoAge ??
                          record.neyziWeightPercentile,
                      Colors.orange,
                      record: record,
                      percentileResult: percentileResult,
                    ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: overWhoWeightLimit
                  ? _buildDisplayBoxWithBorder(
                      context,
                      'Ağırlık Persentili\nWHO',
                      '10 yaşından büyük çocuklar\niçin BKİ kullanınız',
                      Colors.blue,
                      record: record,
                      percentileResult: percentileResult,
                    )
                  : canFlipCards && percentileResult != null
                      ? FlippableCard(
                          frontChild: _buildDisplayBoxWithBorder(
                            context,
                            'Ağırlık Persentili\nWHO (Kronolojik)',
                            percentileResult.whoWeightPercentileChronoAge,
                            Colors.blue,
                            record: record,
                            percentileResult: percentileResult,
                          ),
                          backChild: _buildDisplayBoxWithBorder(
                            context,
                            'Ağırlık Persentili\nWHO (Boy Yaşı)',
                            percentileResult.whoWeightPercentileHeightAge,
                            Colors.blue,
                            record: record,
                            percentileResult: percentileResult,
                            useHeightAgeForPercentiles: true,
                          ),
                        )
                      : _buildDisplayBoxWithBorder(
                          context,
                          'Ağırlık Persentili\nWHO',
                          percentileResult?.whoWeightPercentileChronoAge ??
                              record.whoWeightPercentile,
                          Colors.blue,
                          record: record,
                          percentileResult: percentileResult,
                        ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Boy Persentili
        Row(
          children: [
            Expanded(
              child: _buildDisplayBoxWithBorder(
                context,
                'Boy Persentili\nNEYZİ',
                percentileResult?.neyziHeightPercentile ??
                    record.neyziHeightPercentile,
                Colors.orange,
                record: record,
                percentileResult: percentileResult,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildDisplayBoxWithBorder(
                context,
                'Boy Persentili\nWHO',
                percentileResult?.whoHeightPercentile ??
                    record.whoHeightPercentile,
                Colors.blue,
                record: record,
                percentileResult: percentileResult,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // BKİ Persentili
        Row(
          children: [
            Expanded(
              child: canFlipCards && percentileResult != null
                  ? FlippableCard(
                      frontChild: _buildDisplayBoxWithBorder(
                        context,
                        'BKİ Persentili\nNEYZİ (Kronolojik)',
                        percentileResult.neyzieBmiPercentileChronoAge,
                        Colors.orange,
                        record: record,
                        percentileResult: percentileResult,
                      ),
                      backChild: _buildDisplayBoxWithBorder(
                        context,
                        'BKİ Persentili\nNEYZİ (Boy Yaşı)',
                        percentileResult.neyzieBmiPercentileHeightAge,
                        Colors.orange,
                        record: record,
                        percentileResult: percentileResult,
                        useHeightAgeForPercentiles: true,
                      ),
                    )
                  : _buildDisplayBoxWithBorder(
                      context,
                      'BKİ Persentili\nNEYZİ',
                      percentileResult?.neyzieBmiPercentileChronoAge ??
                          record.neyziBmiPercentile,
                      Colors.orange,
                      record: record,
                      percentileResult: percentileResult,
                    ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: canFlipCards && percentileResult != null
                  ? FlippableCard(
                      frontChild: _buildDisplayBoxWithBorder(
                        context,
                        'BKİ Persentili\nWHO (Kronolojik)',
                        percentileResult.whoBmiPercentileChronoAge,
                        Colors.blue,
                        record: record,
                        percentileResult: percentileResult,
                      ),
                      backChild: _buildDisplayBoxWithBorder(
                        context,
                        'BKİ Persentili\nWHO (Boy Yaşı)',
                        percentileResult.whoBmiPercentileHeightAge,
                        Colors.blue,
                        record: record,
                        percentileResult: percentileResult,
                        useHeightAgeForPercentiles: true,
                      ),
                    )
                  : _buildDisplayBoxWithBorder(
                      context,
                      'BKİ Persentili\nWHO',
                      percentileResult?.whoBmiPercentileChronoAge ??
                          record.whoBmiPercentile,
                      Colors.blue,
                      record: record,
                      percentileResult: percentileResult,
                    ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Boy Yaşı Durumu
        Row(
          children: [
            Expanded(
              child: _buildDisplayBoxWithBorder(
                context,
                'Boy Yaşı Durumu\nNEYZİ',
                percentileResult?.neyziHeightAgeStatus ??
                    record.neyziHeightAgeStatus,
                Colors.orange,
                record: record,
                percentileResult: percentileResult,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildDisplayBoxWithBorder(
                context,
                'Boy Yaşı Durumu\nWHO',
                percentileResult?.whoHeightAgeStatus ??
                    record.whoHeightAgeStatus,
                Colors.blue,
                record: record,
                percentileResult: percentileResult,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildDisplayBoxWithBorder(
    BuildContext context,
    String label,
    String value,
    Color borderColor, {
    required PatientRecord record,
    PercentileCalculationResult? percentileResult,
    bool useHeightAgeForPercentiles = false,
  }) {
    String trimmedValue = value.trim();
    if (trimmedValue.isEmpty) trimmedValue = '-';

    String? chartType;
    if (label.contains('Ağırlık Persentili')) {
      chartType = label.contains('NEYZİ') ? 'neyzi_weight' : 'who_weight';
    } else if (label.contains('Boy Persentili')) {
      chartType = label.contains('NEYZİ') ? 'neyzi_height' : 'who_height';
    } else if (label.contains('BKİ Persentili')) {
      chartType = label.contains('NEYZİ') ? 'neyzi_bmi' : 'who_bmi';
    } else if (label.contains('Boy Yaşı Durumu')) {
      chartType = label.contains('NEYZİ') ? 'neyzi_height' : 'who_height';
    }

    String? ageNote;
    if (label.contains('Boy Persentili')) {
      final heightAge = _resolveHeightAge(label, percentileResult, record);
      if (heightAge != null) {
        ageNote = 'Boy Yaşına Göre (${_formatAgeNote(heightAge)})';
      }
    }

    if (trimmedValue == '-' &&
        label.contains('BKİ Persentili') &&
        label.contains('WHO')) {
      return Container(
        padding: const EdgeInsets.all(12.0),
        decoration: BoxDecoration(
          color: borderColor.withOpacity(0.05),
          border: Border.all(color: borderColor, width: 2),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 12,
                color: borderColor,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              '2 yaştan büyükler için hesaplanır',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    if (trimmedValue.contains('10 yaşından büyük çocuklar')) {
      return Container(
        padding: const EdgeInsets.all(12.0),
        decoration: BoxDecoration(
          color: borderColor.withOpacity(0.05),
          border: Border.all(color: borderColor, width: 2),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              label,
              style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87),
              textAlign: TextAlign.center,
            ),
            const Divider(height: 16),
            Text(
              trimmedValue,
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: Colors.orange),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    if (trimmedValue == '-') {
      return Container(
        padding: const EdgeInsets.all(12.0),
        decoration: BoxDecoration(
          color: Colors.grey[100],
          border: Border.all(color: borderColor, width: 2),
          borderRadius: BorderRadius.circular(4),
        ),
        child: const Text('Veri Yok',
            style: TextStyle(color: Colors.grey, fontSize: 12)),
      );
    }

    return Container(
      padding: const EdgeInsets.all(12.0),
      decoration: BoxDecoration(
        color: borderColor.withOpacity(0.05),
        border: Border.all(color: borderColor, width: 2),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Stack(
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < 260;
              final labelText = Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  color: borderColor,
                ),
                textAlign: isNarrow ? TextAlign.left : TextAlign.center,
                softWrap: true,
                overflow: TextOverflow.ellipsis,
                maxLines: 3,
              );
              final iconWidget = chartType != null
                  ? Tooltip(
                      message: 'Grafiği açmak için tıklayın',
                      waitDuration: const Duration(milliseconds: 200),
                      child: InkWell(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => GrowthChartScreen(
                                patient: record,
                                initialChartType: chartType,
                              ),
                            ),
                          );
                        },
                        borderRadius: BorderRadius.circular(4),
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            border: Border.all(color: Colors.black, width: 2),
                            borderRadius: BorderRadius.circular(4),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.2),
                                blurRadius: 3,
                                offset: const Offset(0, 1),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.show_chart,
                            color: Colors.black,
                            size: 20,
                          ),
                        ),
                      ),
                    )
                  : null;

              Widget labelRow;
              if (isNarrow) {
                labelRow = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    labelText,
                    if (iconWidget != null) ...[
                      const SizedBox(height: 6),
                      Align(alignment: Alignment.centerLeft, child: iconWidget),
                    ],
                  ],
                );
              } else {
                labelRow = Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(child: labelText),
                    if (iconWidget != null)
                      Padding(
                        padding: const EdgeInsets.only(left: 8.0),
                        child: iconWidget,
                      ),
                  ],
                );
              }

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  labelRow,
                  const SizedBox(height: 8),
                  Text(
                    trimmedValue,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      color: Colors.grey[800],
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  _buildPercentileValues(
                    context,
                    record,
                    percentileResult,
                    label,
                    borderColor,
                    trimmedValue,
                    useHeightAgeForPercentiles: useHeightAgeForPercentiles,
                  ),
                ],
              );
            },
          ),
          if (ageNote != null &&
              !label.contains('Kronolojik') &&
              !label.contains('Boy Yaşı'))
            Positioned(
              top: 0,
              left: 0,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final screenWidth = MediaQuery.of(context).size.width;
                  final double fontSize = screenWidth < 600
                      ? 7.5
                      : screenWidth < 900
                          ? 8.5
                          : 9.5;

                  return Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: screenWidth < 600 ? 4 : 6,
                      vertical: screenWidth < 600 ? 2 : 3,
                    ),
                    decoration: BoxDecoration(
                      color: borderColor.withOpacity(0.15),
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(4),
                        bottomRight: Radius.circular(8),
                      ),
                    ),
                    child: Text(
                      ageNote!,
                      style: TextStyle(
                        fontSize: fontSize,
                        fontWeight: FontWeight.w600,
                        color: borderColor.withOpacity(0.9),
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPercentileValues(
    BuildContext context,
    PatientRecord record,
    PercentileCalculationResult? percentileResult,
    String label,
    Color borderColor,
    String value, {
    bool useHeightAgeForPercentiles = false,
  }) {
    String? dataType;
    String? source;

    if (label.contains('Ağırlık Persentili')) {
      dataType = 'weight';
      source = label.contains('NEYZİ') ? 'neyzi' : 'who';
    } else if (label.contains('Boy Persentili')) {
      dataType = 'height';
      source = label.contains('NEYZİ') ? 'neyzi' : 'who';
    } else if (label.contains('BKİ Persentili')) {
      dataType = 'bmi';
      source = label.contains('NEYZİ') ? 'neyzi' : 'who';
    } else if (label.contains('Boy Yaşı Durumu')) {
      if (!value.trim().startsWith('Boy Yaşı')) {
        return const SizedBox.shrink();
      }
      dataType = 'height';
      source = label.contains('NEYZİ') ? 'neyzi' : 'who';
    } else {
      return const SizedBox.shrink();
    }

    final gender = record.selectedGender;
    if (gender.isEmpty) {
      return const SizedBox.shrink();
    }

    int referenceAgeInMonths = record.chronologicalAgeInMonths;
    if (referenceAgeInMonths <= 0) {
      return const SizedBox.shrink();
    }

    final int? neyziHeightAgeFromResult =
        percentileResult?.neyziHeightAgeInMonths;
    final int? neyziHeightAge =
        neyziHeightAgeFromResult != null && neyziHeightAgeFromResult > -1
            ? neyziHeightAgeFromResult
            : (record.neyziHeightAgeInMonths > -1
                ? record.neyziHeightAgeInMonths
                : null);

    final int? whoHeightAgeFromResult = percentileResult?.whoHeightAgeInMonths;
    final int? whoHeightAge =
        whoHeightAgeFromResult != null && whoHeightAgeFromResult > -1
            ? whoHeightAgeFromResult
            : (record.whoHeightAgeInMonths > -1
                ? record.whoHeightAgeInMonths
                : null);

    final bool isNeyzi = source == 'neyzi';
    final int? heightAgeForSource = isNeyzi ? neyziHeightAge : whoHeightAge;

    final bool isHeightAgeBox = label.contains('Boy Yaşı Durumu');
    if ((useHeightAgeForPercentiles || isHeightAgeBox) && heightAgeForSource != null) {
      referenceAgeInMonths = heightAgeForSource;
    }

    final String? ageLabel = referenceAgeInMonths > 0
        ? _formatPercentileAgeLabel(referenceAgeInMonths)
        : null;

    return FutureBuilder<Map<String, double>>(
      future: _getPercentileValuesFromCSV(
          source, dataType, gender, referenceAgeInMonths),
      builder: (context, snapshot) {
        if (!snapshot.hasData ||
            snapshot.data == null ||
            snapshot.data!.isEmpty) {
          return const SizedBox.shrink();
        }

        final values = snapshot.data!;

        String unit = '';
        if (dataType == 'weight') {
          unit = 'kg';
        } else if (dataType == 'height') {
          unit = 'cm';
        } else if (dataType == 'bmi') {
          unit = 'kg/m²';
        }

        return Column(
          children: [
            if (value.isNotEmpty && value != '-') ...[
              const SizedBox(height: 8),
              _buildScalePointer(value),
              const SizedBox(height: 4),
            ],
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              decoration: BoxDecoration(
                color: borderColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      Expanded(
                        child: Text(
                          '%',
                          style: const TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w600,
                              color: Colors.black54),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      _buildPercentileLabel('P3'),
                      _buildPercentileLabel('P10'),
                      _buildPercentileLabel('P25'),
                      _buildPercentileLabel('P50'),
                      _buildPercentileLabel('P75'),
                      _buildPercentileLabel('P90'),
                      _buildPercentileLabel('P97'),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            if (ageLabel != null) ...[
                              Text(
                                ageLabel,
                                style: const TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.black87,
                                ),
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 6),
                            ],
                            Text(
                              unit,
                              style: const TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                color: Colors.black87,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                      _buildPercentileValue(values['p3'] ?? 0),
                      _buildPercentileValue(values['p10'] ?? 0),
                      _buildPercentileValue(values['p25'] ?? 0),
                      _buildPercentileValue(values['p50'] ?? 0),
                      _buildPercentileValue(values['p75'] ?? 0),
                      _buildPercentileValue(values['p90'] ?? 0),
                      _buildPercentileValue(values['p97'] ?? 0),
                    ],
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildPercentileLabel(String label) {
    return Expanded(
      child: Text(
        label,
        style: const TextStyle(
            fontSize: 9, fontWeight: FontWeight.w600, color: Colors.black54),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _buildPercentileValue(double value) {
    return Expanded(
      child: Text(
        value > 0 ? value.toStringAsFixed(1) : '-',
        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _buildScalePointer(String value) {
    double position = 0.5;

    if (value.contains('P<3') ||
        value.contains('< P3') ||
        (value.contains('P3') &&
            (value.contains('Altında') || value.contains('altında')))) {
      position = 0.0625;
    } else if (value.contains('P>97') ||
        value.contains('> P97') ||
        (value.contains('P97') &&
            (value.contains('Üzerinde') || value.contains('üzerinde')))) {
      position = 0.9375;
    } else if (value.contains('P') && value.contains('Arası')) {
      final matches = RegExp(r'P(\d+)').allMatches(value).toList();
      if (matches.length >= 2) {
        final lower = int.parse(matches[0].group(1)!);
        final upper = int.parse(matches[1].group(1)!);

        final percentilePositions = {
          3: 0.125,
          10: 0.25,
          25: 0.375,
          50: 0.5,
          75: 0.625,
          90: 0.75,
          97: 0.875,
        };

        final lowerPos = percentilePositions[lower];
        final upperPos = percentilePositions[upper];

        if (lowerPos != null && upperPos != null) {
          position = (lowerPos + upperPos) / 2;
        }
      }
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final pointerLeft = constraints.maxWidth * (0.125 + position * 0.875);

        return Stack(
          clipBehavior: Clip.none,
          children: [
            SizedBox(
              width: constraints.maxWidth,
              height: 40,
            ),
            Positioned(
              left: pointerLeft - 30,
              top: 0,
              child: SizedBox(
                width: 60,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      value,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      '▼',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<Map<String, double>> _getPercentileValuesFromCSV(
    String source,
    String dataType,
    String gender,
    int ageInMonths,
  ) async {
    try {
      List<dynamic> sourceData;

      if (source == 'who') {
        if (dataType == 'weight') {
          sourceData = gender == 'Erkek'
              ? PersentilData.whoErkekAgirlik
              : PersentilData.whoKadinAgirlik;
        } else if (dataType == 'height') {
          sourceData = gender == 'Erkek'
              ? PersentilData.whoErkekBoy
              : PersentilData.whoKadinBoy;
        } else {
          sourceData = gender == 'Erkek'
              ? PersentilData.whoErkekBmi
              : PersentilData.whoKadinBmi;
        }
      } else {
        if (dataType == 'weight') {
          sourceData = gender == 'Erkek'
              ? PersentilData.neyziErkekAgirlik
              : PersentilData.neyziKadinAgirlik;
        } else if (dataType == 'height') {
          sourceData = gender == 'Erkek'
              ? PersentilData.neyziErkekBoy
              : PersentilData.neyziKadinBoy;
        } else {
          sourceData = gender == 'Erkek'
              ? PersentilData.neyziErkekBmi
              : PersentilData.neyziKadinBmi;
        }
      }

      if (sourceData.isEmpty) return {};

      for (final item in sourceData) {
        if (item.ageInMonths == ageInMonths) {
          return {
            'p3': item.percentile3 as double,
            'p10': item.percentile10 as double,
            'p25': item.percentile25 as double,
            'p50': item.percentile50 as double,
            'p75': item.percentile75 as double,
            'p90': item.percentile90 as double,
            'p97': item.percentile97 as double,
          };
        }
      }

      int minDifference = 999999;
      dynamic closestData;
      for (final item in sourceData) {
        final diff = (item.ageInMonths - ageInMonths).abs();
        if (diff < minDifference) {
          minDifference = diff;
          closestData = item;
        }
      }

      if (closestData != null) {
        return {
          'p3': closestData.percentile3 as double,
          'p10': closestData.percentile10 as double,
          'p25': closestData.percentile25 as double,
          'p50': closestData.percentile50 as double,
          'p75': closestData.percentile75 as double,
          'p90': closestData.percentile90 as double,
          'p97': closestData.percentile97 as double,
        };
      }

      return {};
    } catch (error) {
      debugPrint('Percentile CSV parse error: $error');
      return {};
    }
  }

  String _formatPercentileAgeLabel(int totalMonths) {
    if (totalMonths <= 0) {
      return '0 Ay';
    }
    if (totalMonths < 12) {
      return '$totalMonths Ay';
    }

    final int years = totalMonths ~/ 12;
    final int months = totalMonths % 12;

    if (months == 0) {
      return '$years Yaş ($totalMonths Ay)';
    }

    return '$years Yaş $months Ay ($totalMonths Ay)';
  }

  String _formatChronologicalAge(PatientRecord record,
      {bool includeMonthTotal = false}) {
    final years = record.chronologicalAgeYears;
    final months = record.chronologicalAgeMonths;
    final totalMonths = record.chronologicalAgeInMonths;
    final buffer = StringBuffer('${years} yıl ${months} ay');
    if (includeMonthTotal && totalMonths > 0) {
      buffer.write(' ($totalMonths Ay)');
    }
    return buffer.toString();
  }

  String _formatAgeNote(int months) {
    if (months < 12) {
      return '$months Ay';
    }
    final ageInYears = (months / 12.0).toStringAsFixed(1);
    return '$ageInYears Yıl ($months Ay)';
  }

  int? _resolveHeightAge(String label,
      PercentileCalculationResult? percentileResult, PatientRecord record) {
    final bool isNeyzi = label.contains('NEYZİ');
    final int? resultValue = isNeyzi
        ? percentileResult?.neyziHeightAgeInMonths
        : percentileResult?.whoHeightAgeInMonths;
    if (resultValue != null && resultValue > -1) {
      return resultValue;
    }
    final stored =
        isNeyzi ? record.neyziHeightAgeInMonths : record.whoHeightAgeInMonths;
    return stored > -1 ? stored : null;
  }
}
