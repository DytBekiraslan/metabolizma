import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:provider/provider.dart';
import '../models/models.dart';
import '../services/persentil_service.dart';
import '../services/persentil_calculator.dart';
import '../services/patient_service.dart';
import '../services/auth_service.dart';
import '../widgets/flippable_card.dart';

class GrowthChartScreen extends StatefulWidget {
  final PatientRecord patient;
  final String? initialChartType;

  const GrowthChartScreen({
    Key? key,
    required this.patient,
    this.initialChartType,
  }) : super(key: key);

  @override
  State<GrowthChartScreen> createState() => _GrowthChartScreenState();
}

class _GrowthChartScreenState extends State<GrowthChartScreen> {
  final PersentilService _persentilService = PersentilService();
  final PersentilCalculator _persentilCalculator = PersentilCalculator();
  final PatientService _patientService = PatientService();

  // CSV verisi cache'i
  Map<String, List<PercentileData>> csvDataCache = {};
  Map<String, List<LengthPercentileData>> lengthCsvDataCache = {};
  bool _dataLoaded = false;

  // Aynı hasta için tüm kayıtlar (catch-up growth için)
  List<PatientRecord> _allPatientRecords = [];

  // Seçili grafik tipi
  String? _selectedChartType;

  PercentileCalculationResult? _percentileResult;

  @override
  void initState() {
    super.initState();
    _selectedChartType = widget.initialChartType;
    _calculateCurrentPercentiles();
    _loadData();
  }

  @override
  void didUpdateWidget(GrowthChartScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Hasta bilgileri değiştiyse (örneğin cinsiyet) verileri yeniden yükle
    if (oldWidget.patient.selectedGender != widget.patient.selectedGender ||
        oldWidget.patient.patientName != widget.patient.patientName) {
      _dataLoaded = false;
      _calculateCurrentPercentiles();
      _loadData();
    }
  }

  void _calculateCurrentPercentiles() {
    final patient = widget.patient;
    if (patient.height > 0 &&
        patient.weight > 0 &&
        patient.chronologicalAgeInMonths > 0) {
      _percentileResult = _persentilCalculator.calculateAllPercentiles(
        chronologicalAgeInMonths: patient.chronologicalAgeInMonths,
        gender: patient.selectedGender,
        weight: patient.weight,
        height: patient.height,
      );
    } else {
      _percentileResult = null;
    }
  }

  /// Tüm verileri yükle
  Future<void> _loadData() async {
    final authService = Provider.of<AuthService>(context, listen: false);
    await _patientService.init(authService);
    await _loadCSVData();
    await _loadAllPatientRecords();
  }

  /// Aynı hasta için tüm kayıtları yükle
  Future<void> _loadAllPatientRecords() async {
    try {
      final records = await _patientService
          .getAllPatientRecords(widget.patient.patientName);
      // Tarihe göre sırala (eskiden yeniye)
      records.sort((a, b) => a.recordDate.compareTo(b.recordDate));

      print('DEBUG: Yüklenen kayıt sayısı: ${records.length}');
      for (var record in records) {
        print(
            'DEBUG: Kayıt - Tarih: ${record.recordDate}, Boy: ${record.height}, Ağırlık: ${record.weight}, Yaş(ay): ${record.chronologicalAgeInMonths}');
      }

      if (mounted) {
        setState(() {
          _allPatientRecords = records;
        });
      }
    } catch (e) {
      print('Hasta kayıtları yükleme hatası: $e');
    }
  }

  /// Tüm CSV verilerini yükle
  Future<void> _loadCSVData() async {
    try {
      final gender = widget.patient.selectedGender.toLowerCase() == 'erkek'
          ? 'erkek'
          : 'kadin';

      // WHO verilerini yükle
      csvDataCache['who_weight'] = await _persentilService
          .loadWeightDataFromCSV('who_${gender}_agirlik.csv');
      csvDataCache['who_bmi'] =
          await _persentilService.loadBMIDataFromCSV('who_${gender}_bmi.csv');
      lengthCsvDataCache['who_height'] = await _persentilService
          .loadHeightDataFromCSV('who_${gender}_boy.csv');

      // Neyzi verilerini yükle
      csvDataCache['neyzi_weight'] = await _persentilService
          .loadWeightDataFromCSV('neyzi_${gender}_agirlik.csv');
      csvDataCache['neyzi_bmi'] =
          await _persentilService.loadBMIDataFromCSV('neyzi_${gender}_bmi.csv');
      lengthCsvDataCache['neyzi_height'] = await _persentilService
          .loadHeightDataFromCSV('neyzi_${gender}_boy.csv');

      if (mounted) {
        setState(() {
          _dataLoaded = true;
        });
      }
    } catch (e) {
      print('CSV yükleme hatası: $e');
    }
  }

  /// Bir yaş için verinin mevcut olup olmadığını kontrol et (şu an kullanılmıyor)
  // bool _isDataAvailable(String chartType, int ageInMonths) {
  //   if (chartType.contains('height')) {
  //     final data = lengthCsvDataCache[_getCacheKey(chartType)];
  //     if (data == null || data.isEmpty) return false;
  //     return data.any((d) => d.ageInMonths == ageInMonths);
  //   } else {
  //     final data = csvDataCache[chartType];
  //     if (data == null || data.isEmpty) return false;
  //     return data.any((d) => d.ageInMonths == ageInMonths);
  //   }
  // }

  /// Yaş aralığını kontrol et
  bool _isAgeInRange(String chartType, int ageInMonths) {
    // WHO yaş sınırları - sadece boy için kontrol
    if (chartType == 'who_height' && (ageInMonths < 0 || ageInMonths > 216))
      return false;

    // Neyzi yaş sınırları (0-30 yıl = 0-360 ay)
    if (chartType.contains('neyzi') && (ageInMonths < 0 || ageInMonths > 360))
      return false;

    return true;
  }

  @override
  Widget build(BuildContext context) {
    if (!_dataLoaded) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Büyüme Grafiği'),
          backgroundColor: Colors.blue.shade700,
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    // Hasta bilgilerini al
    final chronoAgeMonths = widget.patient.chronologicalAgeInMonths;
    final chronoAgeYears = widget.patient.chronologicalAgeYears;
    final chronoAgeRemainingMonths = widget.patient.chronologicalAgeMonths;
    final weight = widget.patient.weight;
    final height = widget.patient.height;
    final gender = widget.patient.selectedGender;
    final isMale = gender.toLowerCase() == 'erkek';
    final genderColor = isMale ? Colors.blue : Colors.pink;
    final genderText = isMale ? 'ERKEK' : 'KADIN';

    // BMI hesapla
    double bmi = 0;
    if (height > 0 && weight > 0) {
      double heightInMeters = height / 100.0;
      bmi = weight / (heightInMeters * heightInMeters);
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_selectedChartType != null
            ? _getChartTitle(_selectedChartType!)
            : 'Büyüme Grafiği'),
        backgroundColor: genderColor.shade700,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            // Hasta bilgileri kartı
            Card(
              elevation: 4,
              color: genderColor.shade50,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.patient.patientName,
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildInfoBox(
                            'Yaş',
                            '$chronoAgeYears yıl $chronoAgeRemainingMonths ay\n($chronoAgeMonths ay)',
                            Icons.cake),
                        _buildInfoBox('Cinsiyet', gender, Icons.person),
                        _buildInfoBox(
                            'Boy',
                            height > 0
                                ? '${height.toStringAsFixed(1)} cm'
                                : '-',
                            Icons.height),
                        _buildInfoBox(
                            'Ağırlık',
                            weight > 0
                                ? '${weight.toStringAsFixed(1)} kg'
                                : '-',
                            Icons.monitor_weight),
                        _buildInfoBox(
                            'BKİ',
                            bmi > 0 ? bmi.toStringAsFixed(1) : '-',
                            Icons.analytics),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Eğer specific chart seçilmişse sadece onu göster
            if (_selectedChartType != null) ...[
              _buildChartTile(
                  _getChartTitle(_selectedChartType!), _selectedChartType!),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: () {
                  setState(() {
                    _selectedChartType = null;
                  });
                },
                icon: const Icon(Icons.grid_view),
                label: const Text('Tüm Grafikleri Göster'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: genderColor.shade600,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
              ),
            ] else ...[
              LayoutBuilder(
                builder: (context, constraints) {
                  final isNarrow = constraints.maxWidth < 900;

                  Widget buildChartColumn(
                    String title,
                    List<MapEntry<String, String>> chartConfigs,
                  ) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: genderColor.shade800,
                          ),
                        ),
                        const SizedBox(height: 12),
                        for (int i = 0; i < chartConfigs.length; i++) ...[
                          _buildChartTile(
                            chartConfigs[i].key,
                            chartConfigs[i].value,
                          ),
                          if (i != chartConfigs.length - 1)
                            const SizedBox(height: 12),
                        ],
                      ],
                    );
                  }

                  final neyziColumn = buildChartColumn(
                    'Neyzi Büyüme Grafikleri ($genderText)',
                    [
                      MapEntry('Yaşa Göre Ağırlık', 'neyzi_weight'),
                      MapEntry('Yaşa Göre Boy', 'neyzi_height'),
                      MapEntry('Yaşa Göre BKİ', 'neyzi_bmi'),
                    ],
                  );

                  final whoColumn = buildChartColumn(
                    'WHO Büyüme Grafikleri ($genderText)',
                    [
                      MapEntry('Yaşa Göre Ağırlık', 'who_weight'),
                      MapEntry('Yaşa Göre Boy', 'who_height'),
                      MapEntry('Yaşa Göre BKİ', 'who_bmi'),
                    ],
                  );

                  if (isNarrow) {
                    return Column(
                      children: [
                        neyziColumn,
                        const SizedBox(height: 24),
                        whoColumn,
                      ],
                    );
                  }

                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: neyziColumn),
                      const SizedBox(width: 16),
                      Expanded(child: whoColumn),
                    ],
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _getChartTitle(String chartType) {
    switch (chartType) {
      case 'who_height':
        return 'WHO - Yaşa Göre Boy';
      case 'who_weight':
        return 'WHO - Yaşa Göre Ağırlık';
      case 'who_bmi':
        return 'WHO - Yaşa Göre BKİ';
      case 'neyzi_height':
        return 'Neyzi - Yaşa Göre Boy';
      case 'neyzi_weight':
        return 'Neyzi - Yaşa Göre Ağırlık';
      case 'neyzi_bmi':
        return 'Neyzi - Yaşa Göre BKİ';
      default:
        return 'Büyüme Grafiği';
    }
  }

  Widget _buildChartTile(String title, String chartType) {
    final int? heightAgeForChart = _getHeightAgeForChart(chartType);
    if (heightAgeForChart != null) {
      final kronoAge = widget.patient.chronologicalAgeInMonths;
      final backLabel = 'Boy Yaşı: ${_formatAgeLabel(heightAgeForChart)}';
      return FlippableCard(
        frontChild: _buildChartOrMessage(
          title,
          chartType,
          referenceAgeInMonths: kronoAge,
          viewLabel: 'Kronolojik Yaş',
        ),
        backChild: _buildChartOrMessage(
          title,
          chartType,
          referenceAgeInMonths: heightAgeForChart,
          viewLabel: backLabel,
        ),
      );
    }

    return _buildChartOrMessage(title, chartType);
  }

  bool _isWeightOrBmiChart(String chartType) {
    return chartType.contains('weight') || chartType.contains('bmi');
  }

  int? _getHeightAgeForChart(String chartType) {
    if (!_isWeightOrBmiChart(chartType)) return null;

    final bool isNeyziChart = chartType.contains('neyzi');
    final int? calculatedValue = isNeyziChart
        ? _percentileResult?.neyziHeightAgeInMonths
        : _percentileResult?.whoHeightAgeInMonths;
    if (calculatedValue != null &&
        calculatedValue > -1 &&
        calculatedValue != widget.patient.chronologicalAgeInMonths) {
      return calculatedValue;
    }

    final int storedValue = isNeyziChart
        ? widget.patient.neyziHeightAgeInMonths
        : widget.patient.whoHeightAgeInMonths;
    if (storedValue > -1 &&
        storedValue != widget.patient.chronologicalAgeInMonths) {
      return storedValue;
    }

    return null;
  }

  String _formatAgeLabel(int months) {
    if (months < 12) {
      return '$months Ay';
    }
    final years = months ~/ 12;
    final remainingMonths = months % 12;
    if (remainingMonths == 0) {
      return '$years Yıl';
    }
    return '$years Yıl $remainingMonths Ay';
  }

  Widget _buildInfoBox(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: Colors.blue.shade700, size: 28),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 2),
        Text(value,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center),
      ],
    );
  }

  Widget _buildPercentileInfo(String chartType, int ageInMonths, double value) {
    // Cache'den veriyi al
    final bool usesWeightData =
        chartType.contains('weight') || chartType.contains('bmi');
    final bool hasWeightData = csvDataCache[chartType]?.isNotEmpty ?? false;
    final bool hasHeightData =
        lengthCsvDataCache[chartType]?.isNotEmpty ?? false;

    // Cache boşsa persentil gösterme
    if (usesWeightData && !hasWeightData) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          'Hasta Değeri: ${value.toStringAsFixed(1)} → Persentil: -',
          style: const TextStyle(
              fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey),
        ),
      );
    }

    if (!usesWeightData && !hasHeightData) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          'Hasta Değeri: ${value.toStringAsFixed(1)} → Persentil: -',
          style: const TextStyle(
              fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey),
        ),
      );
    }

    // Yaşa uygun veriyi bul
    PercentileData? ageWeightData;
    LengthPercentileData? ageHeightData;

    if (usesWeightData) {
      ageWeightData = _getClosestWeightPercentile(chartType, ageInMonths);
    } else {
      ageHeightData = _getClosestHeightPercentile(chartType, ageInMonths);
    }

    // Persentil aralığını bul
    String percentileRange = '-';
    if (ageWeightData != null) {
      percentileRange = _findPercentileRange(
          value,
          ageWeightData.percentile3,
          ageWeightData.percentile10,
          ageWeightData.percentile25,
          ageWeightData.percentile50,
          ageWeightData.percentile75,
          ageWeightData.percentile90,
          ageWeightData.percentile97);
    } else if (ageHeightData != null) {
      percentileRange = _findPercentileRange(
          value,
          ageHeightData.percentile3,
          ageHeightData.percentile10,
          ageHeightData.percentile25,
          ageHeightData.percentile50,
          ageHeightData.percentile75,
          ageHeightData.percentile90,
          ageHeightData.percentile97);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.blue.shade100,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        'Hasta Değeri: ${value.toStringAsFixed(1)} → Persentil: $percentileRange',
        style: const TextStyle(
            fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blue),
      ),
    );
  }

  String _findPercentileRange(double value, double p3, double p10, double p25,
      double p50, double p75, double p90, double p97) {
    if (value < p3) return '<P3';
    if (value < p10) return 'P3-P10';
    if (value < p25) return 'P10-P25';
    if (value < p50) return 'P25-P50';
    if (value < p75) return 'P50-P75';
    if (value < p90) return 'P75-P90';
    if (value < p97) return 'P90-P97';
    return '>P97';
  }

  /// Y ekseni için uygun interval hesapla
  double _calculateYInterval(double minY, double maxY) {
    double range = maxY - minY;

    // Aralığa göre dinamik interval
    if (range <= 20) {
      return 2; // Küçük aralıklar için (örn: BMI 10-25)
    } else if (range <= 40) {
      return 5; // Orta aralıklar için (örn: Ağırlık 10-45 kg)
    } else if (range <= 80) {
      return 10; // Büyük aralıklar için (örn: Boy 90-160 cm)
    } else {
      return 20; // Çok büyük aralıklar için
    }
  }

  /// Grafik veya "veri yok" mesajı göster
  Widget _buildChartOrMessage(
    String title,
    String chartType, {
    int? referenceAgeInMonths,
    String? viewLabel,
  }) {
    final ageInMonths =
        referenceAgeInMonths ?? widget.patient.chronologicalAgeInMonths;

    // CSV verileri yüklenmişse kontrol et
    if (!_dataLoaded) {
      return Card(
        elevation: 3,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Text(title,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 16),
              const SizedBox(
                height: 30,
                width: 30,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ],
          ),
        ),
      );
    }

    if (!_isAgeInRange(chartType, ageInMonths)) {
      return Card(
        elevation: 3,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Text(title,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 16),
              Text(
                'Bu yaş için veri yok (${_getAgeRangeMessage(chartType)})',
                style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return _buildChart(
      title,
      chartType,
      referenceAgeInMonths: ageInMonths,
      viewLabel: viewLabel,
    );
  }

  String _getAgeRangeMessage(String chartType) {
    if (chartType == 'who_weight') return '0-10 yıl';
    if (chartType == 'who_height') return '0-18 yıl';
    if (chartType == 'who_bmi') return '2-18 yıl';
    return '0-30 yıl'; // Neyzi
  }

  PercentileData? _getClosestWeightPercentile(String chartType, int ageInMonths) {
    final data = csvDataCache[chartType];
    if (data == null || data.isEmpty) return null;
    return _findNearestEntry<PercentileData>(
      data,
      ageInMonths,
      (entry) => entry.ageInMonths,
    );
  }

  LengthPercentileData? _getClosestHeightPercentile(String chartType, int ageInMonths) {
    final data = lengthCsvDataCache[chartType];
    if (data == null || data.isEmpty) return null;
    return _findNearestEntry<LengthPercentileData>(
      data,
      ageInMonths,
      (entry) => entry.ageInMonths,
    );
  }

  T? _findNearestEntry<T>(
    List<T> data,
    int targetAge,
    int Function(T entry) extractAge,
  ) {
    T? nearest;
    int smallestDiff = 1 << 30;

    for (final entry in data) {
      final diff = (extractAge(entry) - targetAge).abs();
      if (diff < smallestDiff) {
        smallestDiff = diff;
        nearest = entry;
      }
    }

    return nearest;
  }

  Widget _buildChart(
    String title,
    String chartType, {
    required int referenceAgeInMonths,
    String? viewLabel,
  }) {
    final gender = widget.patient.selectedGender;
    final isMale = gender.toLowerCase() == 'erkek';
    final genderColor = isMale ? Colors.blue : Colors.pink;
    final patientColor =
      isMale ? Colors.blue.shade700 : Colors.pink.shade700;
    final bool isWeightOrBmiChart = _isWeightOrBmiChart(chartType);
    final int? heightAgeForChart =
      isWeightOrBmiChart ? _getHeightAgeForChart(chartType) : null;
    final bool isHeightAgeView =
      heightAgeForChart != null && referenceAgeInMonths == heightAgeForChart;
    final chronoAgeMonths = widget.patient.chronologicalAgeInMonths;
    final effectiveAgeInMonths = referenceAgeInMonths;
    double weight = widget.patient.weight > 0 ? widget.patient.weight : 0;
    double height = widget.patient.height > 0 ? widget.patient.height : 0;
    double bmi = 0;

    // BMI hesapla (eğer boy ve kilo varsa)
    if (height > 0 && weight > 0) {
      double heightInMeters = height / 100.0;
      bmi = weight / (heightInMeters * heightInMeters);
    }

    // Persentil info için en son değeri kullan (geçmiş kayıtlardan)
    double? lastRecordValue;
    for (var record in _allPatientRecords.reversed) {
      if (chartType.contains('height') || chartType.contains('boy')) {
        if (record.height > 0) {
          lastRecordValue = record.height;
          break;
        }
      } else if (chartType.contains('bmi')) {
        if (record.height > 0 && record.weight > 0) {
          final heightInMeters = record.height / 100;
          lastRecordValue = record.weight / (heightInMeters * heightInMeters);
          break;
        }
      } else {
        // weight
        if (record.weight > 0) {
          lastRecordValue = record.weight;
          break;
        }
      }
    }

    // Şu anki değer yoksa son kaydı kullan
    if (weight == 0 && height == 0) {
      if (chartType.contains('height') || chartType.contains('boy')) {
        height = lastRecordValue ?? 0;
      } else if (chartType.contains('weight')) {
        weight = lastRecordValue ?? 0;
      } else if (chartType.contains('bmi')) {
        bmi = lastRecordValue ?? 0;
      }
    }

    // Önce Y ekseni aralığını hesapla - hasta verilerine göre dinamik
    double minY = 0;
    double maxY = 100;
    double patientValue = 0;

    // Hasta kayıtlarındaki min ve max değerleri bul
    double? minPatientValue;
    double? maxPatientValue;

    for (var record in _allPatientRecords) {
      double? value;

      if (chartType.contains('height') || chartType.contains('boy')) {
        if (record.height > 0) value = record.height;
      } else if (chartType.contains('bmi')) {
        if (record.height > 0 && record.weight > 0) {
          final heightInMeters = record.height / 100;
          value = record.weight / (heightInMeters * heightInMeters);
        }
      } else {
        // weight
        if (record.weight > 0) value = record.weight;
      }

      if (value != null && value > 0) {
        if (minPatientValue == null || value < minPatientValue) {
          minPatientValue = value;
        }
        if (maxPatientValue == null || value > maxPatientValue) {
          maxPatientValue = value;
        }
      }
    }

    // Hastanın yaşındaki persentil değerlerini al
    PercentileData? ageWeightData;
    LengthPercentileData? ageHeightData;

    if (chartType.contains('weight') || chartType.contains('bmi')) {
      ageWeightData =
          _getClosestWeightPercentile(chartType, effectiveAgeInMonths);
    } else if (chartType.contains('height') || chartType.contains('boy')) {
      ageHeightData =
          _getClosestHeightPercentile(chartType, effectiveAgeInMonths);
    }

    if (chartType.contains('height') || chartType.contains('boy')) {
      patientValue = height;

      // Hasta verilerine göre dinamik Y aralığı
      if (minPatientValue != null && maxPatientValue != null) {
        minY = (minPatientValue * 0.85).floorToDouble(); // %15 altına
        maxY = (maxPatientValue * 1.15).ceilToDouble(); // %15 üstüne

        // Minimum aralık garantisi
        if (maxY - minY < 30) {
          double center = (minY + maxY) / 2;
          minY = center - 15;
          maxY = center + 15;
        }
      } else if (ageHeightData != null) {
        minY = ageHeightData.percentile3 - 10;
        maxY = ageHeightData.percentile97 + 10;
      } else {
        minY = 40;
        maxY = 180;
      }
    } else if (chartType.contains('bmi')) {
      patientValue = bmi;

      // Hasta verilerine göre dinamik Y aralığı
      if (minPatientValue != null && maxPatientValue != null) {
        minY = (minPatientValue * 0.7).floorToDouble();
        maxY = (maxPatientValue * 1.3).ceilToDouble();

        // Minimum aralık garantisi
        if (maxY - minY < 10) {
          double center = (minY + maxY) / 2;
          minY = center - 5;
          maxY = center + 5;
        }
      } else if (ageWeightData != null) {
        minY = ageWeightData.percentile3 - 2;
        maxY = ageWeightData.percentile97 + 2;
      } else {
        minY = 10;
        maxY = 30;
      }
    } else {
      // weight
      patientValue = weight;

      // Hasta verilerine göre dinamik Y aralığı
      if (minPatientValue != null && maxPatientValue != null) {
        minY = (minPatientValue * 0.7).floorToDouble();
        maxY = (maxPatientValue * 1.3).ceilToDouble();

        // Minimum aralık garantisi
        if (maxY - minY < 5) {
          double center = (minY + maxY) / 2;
          minY = center - 2.5;
          maxY = center + 2.5;
        }
      } else if (ageWeightData != null) {
        minY = ageWeightData.percentile3 - 5;
        maxY = ageWeightData.percentile97 + 5;
      } else {
        minY = 0;
        maxY = 100;
      }
    }

    // minY negatif olmasın
    if (minY < 0) minY = 0;

    // Maksimum X değeri: hasta kayıtlarına göre dinamik
    // (Bunu önce hesaplamamız gerek çünkü persentil kontrolünde kullanacağız)

    // Hasta kayıtlarındaki en büyük yaşı bul
    int maxPatientAge = chronoAgeMonths;
    for (var record in _allPatientRecords) {
      if (record.chronologicalAgeInMonths > maxPatientAge) {
        maxPatientAge = record.chronologicalAgeInMonths;
      }
    }

    if (referenceAgeInMonths > maxPatientAge) {
      maxPatientAge = referenceAgeInMonths;
    }

    if (heightAgeForChart != null && heightAgeForChart > maxPatientAge) {
      maxPatientAge = heightAgeForChart;
    }

    // Hasta verilerine göre uygun aralık seç - biraz marj ekle
    int targetAge = maxPatientAge + 12; // 1 yıl marj

    double maxX = 48; // Varsayılan
    if (targetAge <= 24) {
      maxX = 36; // 3 yaş
    } else if (targetAge <= 48) {
      maxX = 72; // 6 yaş
    } else if (targetAge <= 84) {
      maxX = 120; // 10 yaş
    } else if (targetAge <= 144) {
      maxX = 180; // 15 yaş
    } else {
      maxX = chartType.contains('who') ? 216 : 360;
    }

    // Persentil eğrilerindeki min/max değerleri de dikkate al
    // maxX aralığındaki tüm persentil verilerini kontrol et
    if (chartType.contains('height') || chartType.contains('boy')) {
      final data = lengthCsvDataCache[chartType];
      if (data != null) {
        for (var d in data) {
          if (d.ageInMonths <= maxX) {
            if (d.percentile3 < minY) minY = d.percentile3;
            if (d.percentile97 > maxY) maxY = d.percentile97;
          }
        }
      }
    } else {
      // weight or bmi
      final data = csvDataCache[chartType];
      if (data != null) {
        for (var d in data) {
          if (d.ageInMonths <= maxX) {
            if (d.percentile3 < minY) minY = d.percentile3;
            if (d.percentile97 > maxY) maxY = d.percentile97;
          }
        }
      }
    }

    // Biraz margin ekle
    double yMargin = (maxY - minY) * 0.05; // %5 margin
    minY = minY - yMargin;
    maxY = maxY + yMargin;
    if (minY < 0) minY = 0;

    // Y eksenini grid aralığına hizala
    double yInterval = _calculateYInterval(minY, maxY);
    minY = (minY / yInterval).floor() * yInterval;
    maxY = (maxY / yInterval).ceil() * yInterval;

    final lineBars = <LineChartBarData>[];

    // Persentil çizgileri (sabit: 3, 15, 25, 50, 75, 90, 97)
    final persentils = [3, 15, 25, 50, 75, 90, 97];

    for (int p in persentils) {
      lineBars
          .add(_buildPercentileLine(chartType, p, gender, maxX, minY, maxY));
    }

    // Hasta verileri: Tüm kayıtlardan ilgili değerleri al (catch-up growth için)
    List<FlSpot> patientSpots = [];

    print('DEBUG: _allPatientRecords sayısı: ${_allPatientRecords.length}');
    print('DEBUG: chartType: $chartType');

    for (var record in _allPatientRecords) {
      double? value;

      if (chartType == 'who_weight' || chartType == 'neyzi_weight') {
        if (record.weight > 0) {
          value = record.weight;
          print(
              'DEBUG: Ağırlık değeri bulundu: $value, Yaş(ay): ${record.chronologicalAgeInMonths}');
        }
      } else if (chartType == 'who_height' || chartType == 'neyzi_height') {
        if (record.height > 0) {
          value = record.height;
          print(
              'DEBUG: Boy değeri bulundu: $value, Yaş(ay): ${record.chronologicalAgeInMonths}');
        }
      } else if (chartType == 'who_bmi' || chartType == 'neyzi_bmi') {
        if (record.height > 0 && record.weight > 0) {
          final heightInMeters = record.height / 100;
          value = record.weight / (heightInMeters * heightInMeters);
          print(
              'DEBUG: BMI değeri hesaplandı: $value, Yaş(ay): ${record.chronologicalAgeInMonths}');
        }
      }

      if (value != null && value > 0) {
        patientSpots
            .add(FlSpot(record.chronologicalAgeInMonths.toDouble(), value));
        print(
            'DEBUG: FlSpot eklendi: (${record.chronologicalAgeInMonths.toDouble()}, $value)');
      }
    }

    print('DEBUG: Toplam patientSpots sayısı: ${patientSpots.length}');

    // Hasta verilerini ekle (birden fazla kayıt varsa çizgi, tek kayıt varsa sadece nokta)
    if (patientSpots.isNotEmpty && !isHeightAgeView) {
      lineBars.add(_buildPatientDataLine(patientSpots, patientColor));
      print('DEBUG: Patient data line eklendi');
    } else {
      print('DEBUG: UYARI - patientSpots boş!');
    }

    FlSpot? referenceMarker;
    Color? referenceMarkerColor;
    if (patientValue > 0 && isHeightAgeView) {
      referenceMarker =
          FlSpot(referenceAgeInMonths.toDouble(), patientValue.toDouble());
      referenceMarkerColor = Colors.lightBlue.shade600;
      lineBars.add(
        _buildMarkerDot(referenceMarker, referenceMarkerColor),
      );
    }

    return Card(
      elevation: 3,
      color: genderColor.shade50,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (viewLabel != null) ...[
              Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    viewLabel,
                    style: const TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              const SizedBox(height: 6),
            ],
            Text(title,
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            const SizedBox(height: 8),
            // Yaş uyarı mesajları
            if (chartType == 'who_weight' && chronoAgeMonths > 120)
              Container(
                padding: const EdgeInsets.all(8),
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  border: Border.all(color: Colors.orange.shade300),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber_rounded,
                        color: Colors.orange.shade700, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '10 yaşından büyük çocuklar için BKİ kullanınız',
                        style: TextStyle(
                            fontSize: 12,
                            color: Colors.orange.shade900,
                            fontWeight: FontWeight.w500),
                      ),
                    ),
                  ],
                ),
              ),
            if (chartType == 'who_bmi' && chronoAgeMonths < 24)
              Container(
                padding: const EdgeInsets.all(8),
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  border: Border.all(color: Colors.blue.shade300),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline,
                        color: Colors.blue.shade700, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '2 yaşından büyük çocuklar için kullanılır',
                        style: TextStyle(
                            fontSize: 12,
                            color: Colors.blue.shade900,
                            fontWeight: FontWeight.w500),
                      ),
                    ),
                  ],
                ),
              ),
            // Persentil bilgisi (mavi nokta için)
            _buildPercentileInfo(chartType, effectiveAgeInMonths, patientValue),
            const SizedBox(height: 8),
            SizedBox(
              height: 280,
              child: LineChart(
                LineChartData(
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: true,
                    horizontalInterval: _calculateYInterval(minY, maxY),
                    verticalInterval: maxX <= 24 ? 3 : (maxX <= 72 ? 6 : 12),
                  ),
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 40,
                        interval: _calculateYInterval(minY, maxY),
                        getTitlesWidget: (value, meta) => Text(
                            value.toStringAsFixed(0),
                            style: const TextStyle(fontSize: 10)),
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        interval: maxX <= 24
                            ? 3
                            : (maxX <= 72 ? 6 : 12), // Dinamik interval
                        getTitlesWidget: (value, meta) {
                          // Ay/Yıl formatında gösterim
                          if (maxX <= 36) {
                            // 36 ay ve altı: ay olarak göster
                            return Text('${value.toInt()}a',
                                style: const TextStyle(fontSize: 9));
                          } else {
                            // 36 ayın üstü: yıl olarak göster
                            if (value % 12 == 0) {
                              return Text('${(value / 12).toStringAsFixed(0)}y',
                                  style: const TextStyle(fontSize: 9));
                            }
                            return const Text('');
                          }
                        },
                      ),
                    ),
                    topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                  ),
                  borderData: FlBorderData(show: true),
                  lineBarsData: lineBars,
                  minX: 0,
                  maxX: maxX,
                  minY: minY,
                  maxY: maxY,
                ),
              ),
            ),
            const SizedBox(height: 8),
            _buildLegend(
              persentils,
              patientColor: !isHeightAgeView && patientSpots.isNotEmpty
                  ? patientColor
                  : null,
              showHeightAgeMarker: referenceMarker != null,
            ),
          ],
        ),
      ),
    );
  }

  LineChartBarData _buildPercentileLine(String chartType, int percentile,
      String gender, double maxX, double minY, double maxY) {
    List<FlSpot> spots = [];

    // Cache'den ilgili verileri al
    List<PercentileData>? weightData;
    List<LengthPercentileData>? heightData;

    if (chartType == 'who_weight') {
      weightData = csvDataCache['who_weight'];
    } else if (chartType == 'neyzi_weight') {
      weightData = csvDataCache['neyzi_weight'];
    } else if (chartType == 'who_height') {
      heightData = lengthCsvDataCache['who_height'];
    } else if (chartType == 'neyzi_height') {
      heightData = lengthCsvDataCache['neyzi_height'];
    } else if (chartType == 'who_bmi') {
      weightData = csvDataCache['who_bmi'];
    } else if (chartType == 'neyzi_bmi') {
      weightData = csvDataCache['neyzi_bmi'];
    }

    // Persentil değerini field adından al
    // Kullanılan persentiller: 3, 15, 25, 50, 75, 90, 97
    late double Function(dynamic) getPercentileValue;

    switch (percentile) {
      case 3:
        getPercentileValue = (data) => (data as dynamic).percentile3;
        break;
      case 15:
        getPercentileValue =
            (data) => (data as dynamic).percentile10; // 15 → 10 (en yakın)
        break;
      case 25:
        getPercentileValue = (data) => (data as dynamic).percentile25;
        break;
      case 50:
        getPercentileValue = (data) => (data as dynamic).percentile50;
        break;
      case 75:
        getPercentileValue = (data) => (data as dynamic).percentile75;
        break;
      case 90:
        getPercentileValue = (data) => (data as dynamic).percentile90;
        break;
      case 97:
        getPercentileValue = (data) => (data as dynamic).percentile97;
        break;
      default:
        getPercentileValue = (data) => 0.0;
    }

    // Weight veya BMI verisi - sadece maxX aralığındaki noktalar
    if (weightData != null && weightData.isNotEmpty) {
      for (var data in weightData) {
        // Sadece maxX aralığındaki değerleri ekle (Y filtreleme yok, 0'dan başlıyor)
        if (data.ageInMonths <= maxX) {
          double value = getPercentileValue(data);
          if (value > 0) {
            spots.add(FlSpot(data.ageInMonths.toDouble(), value));
          }
        }
      }
    }

    // Height verisi - sadece maxX aralığındaki noktalar
    if (heightData != null && heightData.isNotEmpty) {
      for (var data in heightData) {
        // Sadece maxX aralığındaki değerleri ekle (Y filtreleme yok, 0'dan başlıyor)
        if (data.ageInMonths <= maxX) {
          double value = getPercentileValue(data);
          if (value > 0) {
            spots.add(FlSpot(data.ageInMonths.toDouble(), value));
          }
        }
      }
    }

    return LineChartBarData(
      spots: spots,
      isCurved: true,
      color: _getPercentileColor(percentile),
      barWidth: 2.0, // Daha kalın çizgiler
      dashArray: null, // Düz çizgi (kesikli değil)
      isStrokeCapRound: true,
      dotData: FlDotData(show: false),
    );
  }

  LineChartBarData _buildPatientDataLine(
      List<FlSpot> spots, Color patientColor) {
    // Birden fazla nokta varsa çizgi göster (catch-up growth takibi için)
    final bool showLine = spots.length > 1;

    return LineChartBarData(
      spots: spots,
      isCurved: true, // Yumuşak eğri
      color: patientColor,
      barWidth: showLine ? 3.0 : 0, // Birden fazla nokta varsa çizgi göster
      dotData: FlDotData(
        show: true,
        getDotPainter: (spot, percent, barData, index) => FlDotCirclePainter(
          radius: 6,
          color: patientColor,
          strokeWidth: 2,
          strokeColor: Colors.white,
        ),
      ),
    );
  }

  LineChartBarData _buildMarkerDot(FlSpot spot, Color color) {
    return LineChartBarData(
      spots: [spot],
      isCurved: false,
      color: color,
      barWidth: 0,
      dotData: FlDotData(
        show: true,
        getDotPainter: (spot, percent, barData, index) =>
            FlDotCirclePainter(
          radius: 7,
          color: color,
          strokeWidth: 2,
          strokeColor: Colors.white,
        ),
      ),
    );
  }

  Color _getPercentileColor(int percentile) {
    // Sitedeki gibi farklı renkler
    switch (percentile) {
      case 3:
        return Colors.red.shade600;
      case 15: // P10 olarak çiziliyor
        return Colors.orange.shade400;
      case 25:
        return Colors.blue.shade400;
      case 50:
        return Colors.green.shade600;
      case 75:
        return Colors.purple.shade400;
      case 90:
        return Colors.pink.shade400;
      case 97:
        return Colors.brown.shade400;
      default:
        return Colors.grey;
    }
  }

  Widget _buildLegend(
    List<int> persentils, {
    Color? patientColor,
    bool showHeightAgeMarker = false,
  }) {
    final legendItems = <Widget>[
      for (final p in persentils)
        _buildLegendChip('P$p', _getPercentileColor(p)),
    ];

    if (patientColor != null) {
      legendItems.add(_buildLegendChip('Hasta Eğrisi', patientColor));
    }

    if (showHeightAgeMarker) {
      legendItems.add(
        _buildLegendChip('Boy Yaşı Noktası', Colors.lightBlue.shade600),
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: legendItems,
    );
  }

  Widget _buildLegendChip(String label, Color color) {
    return Chip(
      label: Text(label,
          style: const TextStyle(fontSize: 10, color: Colors.white)),
      backgroundColor: color,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    );
  }
}
