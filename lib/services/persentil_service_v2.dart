// lib/services/persentil_service_v2.dart - TAMAMEN CSV-TABANI VERİ İŞLEME
import '../models/models.dart';
import 'package:collection/collection.dart';
import 'package:flutter/services.dart';
import 'persentil_data.dart';

class PersentilService {

  // ===== EN YAKKIN YAŞ DEĞERİNİ DÖNDÜR (İNTERPOLASYON YOK) =====
  int getHeightAgeInMonths({
    required double height,
    required String gender,
    required int chronologicalAgeInMonths,
  }) {
    return _getHeightAgeClosestMatch(
      height: height,
      gender: gender,
      chronologicalAgeInMonths: chronologicalAgeInMonths,
      source: 'neyzi',
    );
  }

  int getWhoHeightAgeInMonths({
    required double height,
    required String gender,
    required int chronologicalAgeInMonths,
  }) {
    return _getHeightAgeClosestMatch(
      height: height,
      gender: gender,
      chronologicalAgeInMonths: chronologicalAgeInMonths,
      source: 'who',
    );
  }

  // EN YAKKIN P50 YAŞ - INTERPOLASYON YOK!
  int _getHeightAgeClosestMatch({
    required double height,
    required String gender,
    required int chronologicalAgeInMonths,
    required String source,
  }) {
    if (height <= 0) return chronologicalAgeInMonths;

    // Kaynak seçimi
    late List<LengthPercentileData> sourceData;
    if (source == 'who') {
      sourceData = _getWhoHeightData(); // CSV'den yükle
    } else {
      sourceData = _getNeyziHeightData(); // CSV'den yükle
    }

    final List<LengthPercentileData> filtered =
        sourceData.where((d) => d.gender == gender).toList();

    if (filtered.isEmpty) return chronologicalAgeInMonths;

    // P50 değerleri çıkar
    final List<({int ageInMonths, double p50})> p50List = filtered
        .map((d) => (ageInMonths: d.ageInMonths, p50: d.percentile50))
        .toList();

    if (p50List.isEmpty) return chronologicalAgeInMonths;

    // EN YAKKIN P50'Yİ BULLA - INTERPOLASYON YOK
    double minDiff = double.infinity;
    int closestAge = chronologicalAgeInMonths;

    for (final item in p50List) {
      final diff = (item.p50 - height).abs();
      if (diff < minDiff) {
        minDiff = diff;
        closestAge = item.ageInMonths;
      }
    }

    print('DEBUG HEIGHT AGE: height=$height, source=$source, closestAge=$closestAge, chronologicalAge=$chronologicalAgeInMonths');

    return closestAge;
  }

  // ===== CSV VERİ YÜKLEME =====
  List<LengthPercentileData> _getNeyziHeightData() {
    // TAMAMEN HARDCODED VERİ - PersentilData'dan döndür
    final allData = <LengthPercentileData>[
      ...PersentilData.neyziErkekBoy,
      ...PersentilData.neyziKadinBoy,
    ];
    return allData;
  }

  List<LengthPercentileData> _getWhoHeightData() {
    // TAMAMEN HARDCODED VERİ - PersentilData'dan döndür
    final allData = <LengthPercentileData>[
      ...PersentilData.whoErkekBoy,
      ...PersentilData.whoKadinBoy,
    ];
    return allData;
  }

  // Diğer tüm metodlar boş/placeholder (future implementation)
  List<PercentileData> get whoPercentileData => [];
  List<PercentileData> get neyziWeightPercentileData => [];
  List<LengthPercentileData> get neyziHeightPercentileData =>
      _getNeyziHeightData();
  List<LengthPercentileData> get whoHeightPercentileData =>
      _getWhoHeightData();
  List<BMIPercentileData> get whoBmiPercentileData => [];

  // Placeholder metodlar - uyarı: uygulamada kullanılmayacak
  double getPercentileWeight({
    required PercentileSource source,
    required int ageInMonths,
    required String gender,
    required double percentileValue,
  }) {
    // Hangi veri setini kullanacağımızı belirle
    List<PercentileData> dataset;
    if (source == PercentileSource.who) {
      dataset = _getWhoWeightData(gender);
    } else {
      dataset = _getNeyziWeightData(gender);
    }

    // Yaş için veriyi bul (tam eşleşme yoksa en yakını)
    PercentileData? data = dataset.firstWhereOrNull((d) => d.ageInMonths == ageInMonths);
    data ??= _getClosestPercentileData(dataset, ageInMonths);
    if (data == null) return 0.0;

    // Persentil değerine göre ağırlığı döndür
    return data.getWeightByPercentile(percentileValue);
  }

  PercentileData? _getClosestPercentileData(List<PercentileData> dataset, int ageInMonths) {
    if (dataset.isEmpty) return null;

    PercentileData? closest;
    int minDiff = 9999;

    for (final entry in dataset) {
      final diff = (entry.ageInMonths - ageInMonths).abs();
      if (closest == null || diff < minDiff || (diff == minDiff && entry.ageInMonths > closest.ageInMonths)) {
        closest = entry;
        minDiff = diff;
      }
    }

    return closest;
  }

  Future<String> getPercentileRangeFromCSV({
    required String source,
    required String type,
    required String gender,
    required int ageInMonths,
    required double value,
  }) async =>
      "-";

  // ===== CSV LOADING METHODS =====
  Future<List<PercentileData>> loadWeightDataFromCSV(String fileName) async {
    try {
      final csvString = await rootBundle.loadString('assets/persentil_data/$fileName');
      final lines = csvString.split('\n').where((line) => line.trim().isNotEmpty).toList();
      
      if (lines.isEmpty) return [];
      
      // İlk satırı header olarak atla
      final dataLines = lines.skip(1);
      final List<PercentileData> result = [];
      
      // Cinsiyet filename'den çıkar
      final gender = fileName.contains('erkek') ? 'Erkek' : 'Kadın';
      
      for (final line in dataLines) {
        final parts = line.split(',');
        if (parts.length < 8) continue;
        
        try {
          result.add(PercentileData(
            ageInMonths: int.parse(parts[0].trim()),
            percentile3: double.parse(parts[1].trim()),
            percentile10: double.parse(parts[2].trim()),
            percentile25: double.parse(parts[3].trim()),
            percentile50: double.parse(parts[4].trim()),
            percentile75: double.parse(parts[5].trim()),
            percentile90: double.parse(parts[6].trim()),
            percentile97: double.parse(parts[7].trim()),
            gender: gender,
          ));
        } catch (e) {
          print('CSV parse error in line: $line - $e');
        }
      }
      
      print('Loaded ${result.length} weight records from $fileName');
      return result;
    } catch (e) {
      print('Error loading CSV $fileName: $e');
      return [];
    }
  }

  Future<List<LengthPercentileData>> loadHeightDataFromCSV(String fileName) async {
    try {
      final csvString = await rootBundle.loadString('assets/persentil_data/$fileName');
      final lines = csvString.split('\n').where((line) => line.trim().isNotEmpty).toList();
      
      if (lines.isEmpty) return [];
      
      // İlk satırı header olarak atla
      final dataLines = lines.skip(1);
      final List<LengthPercentileData> result = [];
      
      // Cinsiyet filename'den çıkar
      final gender = fileName.contains('erkek') ? 'Erkek' : 'Kadın';
      
      for (final line in dataLines) {
        final parts = line.split(',');
        if (parts.length < 8) continue;
        
        try {
          result.add(LengthPercentileData(
            ageInMonths: int.parse(parts[0].trim()),
            percentile3: double.parse(parts[1].trim()),
            percentile10: double.parse(parts[2].trim()),
            percentile25: double.parse(parts[3].trim()),
            percentile50: double.parse(parts[4].trim()),
            percentile75: double.parse(parts[5].trim()),
            percentile90: double.parse(parts[6].trim()),
            percentile97: double.parse(parts[7].trim()),
            gender: gender,
          ));
        } catch (e) {
          print('CSV parse error in line: $line - $e');
        }
      }
      
      print('Loaded ${result.length} height records from $fileName');
      return result;
    } catch (e) {
      print('Error loading CSV $fileName: $e');
      return [];
    }
  }

  Future<List<PercentileData>> loadBMIDataFromCSV(String fileName) async {
    // BMI verisi de weight data formatında
    return loadWeightDataFromCSV(fileName);
  }

  // ===== PERCENTILE RANGE CALCULATION =====
  String getHeightPercentileRange({
    required int ageInMonths,
    required String gender,
    required double height,
  }) {
    if (height <= 0) return "-";
    
    // Get the Neyzi data
    final sourceData = _getNeyziHeightData();
    final filtered = sourceData.where((d) => d.gender == gender).toList();
    
    if (filtered.isEmpty) return "-";
    
    // Find closest age
    final closestData = filtered.fold<LengthPercentileData?>(null, (closest, current) {
      if (closest == null) return current;
      final closestDiff = (closest.ageInMonths - ageInMonths).abs();
      final currentDiff = (current.ageInMonths - ageInMonths).abs();
      return currentDiff < closestDiff ? current : closest;
    });
    
    if (closestData == null) return "-";
    
    // Determine percentile range
    final p3 = closestData.percentile3;
    final p10 = closestData.percentile10;
    final p25 = closestData.percentile25;
    final p50 = closestData.percentile50;
    final p75 = closestData.percentile75;
    final p90 = closestData.percentile90;
    final p97 = closestData.percentile97;
    
    const epsilon = 0.01;
    if (height < p3 - epsilon) return "< P3";
    if (height < p10 - epsilon) return "P3-P10 Arası";
    if (height < p25 - epsilon) return "P10-P25 Arası";
    if (height < p50 - epsilon) return "P25-P50 Arası";
    if (height < p75 - epsilon) return "P50-P75 Arası";
    if (height < p90 - epsilon) return "P75-P90 Arası";
    if (height < p97 - epsilon) return "P90-P97 Arası";
    return "> P97";
  }

  // Ağırlık Persentili Aralığı Hesapla
  String getWeightPercentileRange({
    required int ageInMonths,
    required String gender,
    required double weight,
  }) {
    if (weight <= 0) return "-";
    
    final data = _getNeyziWeightData(gender);
    if (data.isEmpty) return "-";

    // En yakın yaşı bul
    int closestAge = data[0].ageInMonths;
    double minDiff = (data[0].percentile50 - weight).abs();

    for (final item in data) {
      final diff = (item.percentile50 - weight).abs();
      if (diff < minDiff) {
        minDiff = diff;
        closestAge = item.ageInMonths;
      }
    }

    // Closest data bul
    final PercentileData? item = data.firstWhereOrNull((d) => d.ageInMonths == closestAge);
    if (item == null) return "-";

    // Ağırlığı persentilleriyle karşılaştır
    const epsilon = 0.1;
    if (weight < item.percentile3 - epsilon) return "< P3";
    if (weight < item.percentile10 - epsilon) return "P3-P10 Arası";
    if (weight < item.percentile25 - epsilon) return "P10-P25 Arası";
    if (weight < item.percentile50 - epsilon) return "P25-P50 Arası";
    if (weight < item.percentile75 - epsilon) return "P50-P75 Arası";
    if (weight < item.percentile90 - epsilon) return "P75-P90 Arası";
    if (weight < item.percentile97 - epsilon) return "P90-P97 Arası";
    return "> P97";
  }

  // BKİ Persentili Aralığı Hesapla
  String getBMIPercentileRange({
    required int ageInMonths,
    required String gender,
    required double bmi,
  }) {
    if (bmi <= 0) return "-";

    final data = _getNeyuziBmiData(gender); // Neyzi BMI data kullan
    if (data.isEmpty) return "-";

    // En yakın yaşı bul
    int closestAge = data[0].ageInMonths;
    double minDiff = (data[0].ageInMonths - ageInMonths).abs().toDouble();

    for (final item in data) {
      final diff = (item.ageInMonths - ageInMonths).abs().toDouble();
      if (diff < minDiff) {
        minDiff = diff;
        closestAge = item.ageInMonths;
      }
    }

    // Closest data bul
    final BMIPercentileData? item = data.firstWhereOrNull((d) => d.ageInMonths == closestAge);
    if (item == null) return "-";

    // BKİ'yi persentilleriyle karşılaştır (CSV formatı: P3, P10, P25, P50, P75, P90, P97)
    const epsilon = 0.1;
    if (bmi < item.percentile3 - epsilon) return "< P3";
    if (bmi < item.percentile10 - epsilon) return "P3-P10 Arası";
    if (bmi < item.percentile25 - epsilon) return "P10-P25 Arası";
    if (bmi < item.percentile50 - epsilon) return "P25-P50 Arası";
    if (bmi < item.percentile75 - epsilon) return "P50-P75 Arası";
    if (bmi < item.percentile90 - epsilon) return "P75-P90 Arası";
    if (bmi < item.percentile97 - epsilon) return "P90-P97 Arası";
    return "> P97";
  }

  // ===== WHO BOY PERSENTİLİ ARALĞI =====
  String getWhoHeightPercentileRange({
    required int ageInMonths,
    required String gender,
    required double height,
  }) {
    if (height <= 0) return "-";

    final filtered = _getWhoHeightData().where((d) => d.gender == gender).toList();
    if (filtered.isEmpty) return "-";

    // En yakın yaşı bul (ageInMonths kullanarak)
    int closestAge = filtered[0].ageInMonths;
    double minDiff = (filtered[0].ageInMonths - ageInMonths).abs().toDouble();

    for (final item in filtered) {
      final diff = (item.ageInMonths - ageInMonths).abs().toDouble();
      if (diff < minDiff) {
        minDiff = diff;
        closestAge = item.ageInMonths;
      }
    }

    // Closest data bul
    final LengthPercentileData? data = filtered.firstWhereOrNull((d) => d.ageInMonths == closestAge);
    if (data == null) return "-";

    // Boy ölçüsünü persentilleriyle karşılaştır
    const epsilon = 0.1;
    if (height < data.percentile3 - epsilon) return "< P3";
    if (height < data.percentile10 - epsilon) return "P3-P10 Arası";
    if (height < data.percentile25 - epsilon) return "P10-P25 Arası";
    if (height < data.percentile50 - epsilon) return "P25-P50 Arası";
    if (height < data.percentile75 - epsilon) return "P50-P75 Arası";
    if (height < data.percentile90 - epsilon) return "P75-P90 Arası";
    if (height < data.percentile97 - epsilon) return "P90-P97 Arası";
    return "> P97";
  }

  // ===== WHO AĞIRLIK PERSENTİLİ ARALĞI =====
  String getWhoWeightPercentileRange({
    required int ageInMonths,
    required String gender,
    required double weight,
  }) {
    if (weight <= 0) return "-";
    
    final data = _getWhoWeightData(gender);
    if (data.isEmpty) return "-";

    // En yakın yaşı bul
    int closestAge = data[0].ageInMonths;
    double minDiff = (data[0].percentile50 - weight).abs();

    for (final item in data) {
      final diff = (item.percentile50 - weight).abs();
      if (diff < minDiff) {
        minDiff = diff;
        closestAge = item.ageInMonths;
      }
    }

    // Closest data bul
    final PercentileData? item = data.firstWhereOrNull((d) => d.ageInMonths == closestAge);
    if (item == null) return "-";

    // Ağırlığı persentilleriyle karşılaştır
    const epsilon = 0.1;
    if (weight < item.percentile3 - epsilon) return "< P3";
    if (weight < item.percentile10 - epsilon) return "P3-P10 Arası";
    if (weight < item.percentile25 - epsilon) return "P10-P25 Arası";
    if (weight < item.percentile50 - epsilon) return "P25-P50 Arası";
    if (weight < item.percentile75 - epsilon) return "P50-P75 Arası";
    if (weight < item.percentile90 - epsilon) return "P75-P90 Arası";
    if (weight < item.percentile97 - epsilon) return "P90-P97 Arası";
    return "> P97";
  }

  // ===== WHO BKİ PERSENTİLİ ARALĞI =====
  String getWhoBmiPercentileRange({
    required int ageInMonths,
    required String gender,
    required double bmi,
  }) {
    if (bmi <= 0) return "-";

    final data = _getWhoBmiData(gender); // WHO BMI data kullan
    if (data.isEmpty) return "-";

    // En yakın yaşı bul
    int closestAge = data[0].ageInMonths;
    double minDiff = (data[0].ageInMonths - ageInMonths).abs().toDouble();

    for (final item in data) {
      final diff = (item.ageInMonths - ageInMonths).abs().toDouble();
      if (diff < minDiff) {
        minDiff = diff;
        closestAge = item.ageInMonths;
      }
    }

    // Closest data bul
    final BMIPercentileData? item = data.firstWhereOrNull((d) => d.ageInMonths == closestAge);
    if (item == null) return "-";

    // BKİ'yi persentilleriyle karşılaştır (CSV formatı: P3, P10, P25, P50, P75, P90, P97)
    const epsilon = 0.1;
    if (bmi < item.percentile3 - epsilon) return "< P3";
    if (bmi < item.percentile10 - epsilon) return "P3-P10 Arası";
    if (bmi < item.percentile25 - epsilon) return "P10-P25 Arası";
    if (bmi < item.percentile50 - epsilon) return "P25-P50 Arası";
    if (bmi < item.percentile75 - epsilon) return "P50-P75 Arası";
    if (bmi < item.percentile90 - epsilon) return "P75-P90 Arası";
    if (bmi < item.percentile97 - epsilon) return "P90-P97 Arası";
    return "> P97";
  }

  // ===== NEYZI AĞIRLIK VERİ GETİRME =====
  List<PercentileData> _getNeyziWeightData(String gender) {
    if (gender == 'Erkek') {
      return PersentilData.neyziErkekAgirlik;
    } else {
      return PersentilData.neyziKadinAgirlik;
    }
  }

  // ===== WHO AĞIRLIK VERİ GETİRME =====
  List<PercentileData> _getWhoWeightData(String gender) {
    if (gender == 'Erkek') {
      return PersentilData.whoErkekAgirlik;
    } else {
      return PersentilData.whoKadinAgirlik;
    }
  }

  // ===== NEYZI BKİ VERİ GETİRME =====
  List<BMIPercentileData> _getNeyuziBmiData(String gender) {
    if (gender == 'Erkek') {
      return PersentilData.neyziErkekBmi;
    } else {
      return PersentilData.neyziKadinBmi;
    }
  }

  // ===== WHO BKİ VERİ GETİRME =====
  List<BMIPercentileData> _getWhoBmiData(String gender) {
    if (gender == 'Erkek') {
      return PersentilData.whoErkekBmi;
    } else {
      return PersentilData.whoKadinBmi;
    }
  }
}

