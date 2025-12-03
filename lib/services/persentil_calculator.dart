// lib/services/persentil_calculator.dart
// Merkezi Persentil Hesaplama Servisi
// Tüm persentil hesaplamaları burada yapılır

import '../models/models.dart';
import 'persentil_data.dart';
import 'persentil_service_v2.dart';

class PersentilCalculator {
  final PersentilService _persentilService = PersentilService();

  // Public getter for persentilService
  PersentilService get persentilService => _persentilService;

  // ===== BOY YAŞI HESAPLAMA (BOY PERSENTİLİ < P3 İSE) =====
  /// Çocuğun boy yaşını hesapla (eğer boy persentili P3'ten düşükse)
  /// 
  /// Mantık:
  /// 1. Çocuğun yaşındaki boy persentili (P50) < P3 ise
  /// 2. Çocuğun şu anki boyu ile hangi yaş tablosunda P50'ye en yakın ise
  /// 3. O yaş = Boy Yaşı
  /// 
  /// Parametreler:
  /// - [height]: Çocuğun boyu (cm)
  /// - [chronologicalAgeInMonths]: Kronolojik yaş (ay cinsinden)
  /// - [gender]: Cinsiyet ('Erkek' veya 'Kadın')
  /// - [source]: Veri kaynağı ('neyzi' veya 'who')
  /// 
  /// Döndürüm:
  /// - Boy yaşı (ay cinsinden), eğer hesaplanabilmişse
  /// - -1 eğer boy yaşı hesaplanamadıysa (normal durum)
  int calculateHeightAge({
    required double height,
    required int chronologicalAgeInMonths,
    required String gender,
    required String source, // 'neyzi' or 'who'
  }) {
    if (height <= 0) return -1;

    // 1. Çocuğun yaşındaki boy persentilini kontrol et
    final heightPercentileRange = source == 'neyzi'
        ? _persentilService.getHeightPercentileRange(
            ageInMonths: chronologicalAgeInMonths,
            gender: gender,
            height: height,
          )
        : _persentilService.getWhoHeightPercentileRange(
            ageInMonths: chronologicalAgeInMonths,
            gender: gender,
            height: height,
          );

    // Eğer persentili P3'ten büyükse, boy yaşı hesaplama
    if (!heightPercentileRange.contains("< P3") && !heightPercentileRange.contains("P3-P10")) {
      return -1; // Normal, boy yaşı yok
    }

    // 2. Veri kaynağına göre tüm boy verilerini al
    final List<LengthPercentileData> heightData = source == 'neyzi'
        ? [
            ...PersentilData.neyziErkekBoy,
            ...PersentilData.neyziKadinBoy,
          ]
        : [
            ...PersentilData.whoErkekBoy,
            ...PersentilData.whoKadinBoy,
          ];

    // 3. Cinsiyete göre filtrele
    final genderFiltered = heightData.where((d) => d.gender == gender).toList();
    if (genderFiltered.isEmpty) return -1;

    // 4. Çocuğun boyu ile P50'leri karşılaştırarak en yakın yaşı bul
    double minDiff = double.infinity;
    int closestHeightAge = -1;

    for (final data in genderFiltered) {
      final diff = (data.percentile50 - height).abs();
      if (diff < minDiff) {
        minDiff = diff;
        closestHeightAge = data.ageInMonths;
      }
    }

    print(
        'DEBUG CALCULATE HEIGHT AGE: height=$height, chronAge=$chronologicalAgeInMonths, source=$source, closestHeightAge=$closestHeightAge, minDiff=$minDiff');

    return closestHeightAge > 0 ? closestHeightAge : -1;
  }

  // ===== BİRLEŞTİRİLMİŞ PERSENTIL HESAPLAMASI =====
  /// Verilen yaş, ağırlık, boy için tüm persentil değerlerini hesapla
  PercentileCalculationResult calculateAllPercentiles({
    required int chronologicalAgeInMonths,
    required String gender,
    required double weight,
    required double height,
  }) {
    // Boy yaşını hesapla (Neyzi'ye göre)
    final neyziHeightAge =
        calculateHeightAge(
          height: height,
          chronologicalAgeInMonths: chronologicalAgeInMonths,
          gender: gender,
          source: 'neyzi',
        );

    // Boy yaşını hesapla (WHO'ya göre)
    final whoHeightAge = calculateHeightAge(
      height: height,
      chronologicalAgeInMonths: chronologicalAgeInMonths,
      gender: gender,
      source: 'who',
    );

    // Kronolojik yaş'a göre persentiller
    final neyziWeightPercentileChronoAge = _persentilService
        .getWeightPercentileRange(
          ageInMonths: chronologicalAgeInMonths,
          gender: gender,
          weight: weight,
        );

    final whoWeightPercentileChronoAge = _persentilService
        .getWhoWeightPercentileRange(
          ageInMonths: chronologicalAgeInMonths,
          gender: gender,
          weight: weight,
        );

    final neyziHeightPercentile = _persentilService
        .getHeightPercentileRange(
          ageInMonths: chronologicalAgeInMonths,
          gender: gender,
          height: height,
        );

    final whoHeightPercentile = _persentilService
        .getWhoHeightPercentileRange(
          ageInMonths: chronologicalAgeInMonths,
          gender: gender,
          height: height,
        );

    // BMI hesapla
    double bmi = 0;
    if (height > 0 && weight > 0) {
      double heightInMeters = height / 100.0;
      bmi = weight / (heightInMeters * heightInMeters);
    }

    final neyzieBmiPercentileChronoAge = _persentilService
        .getBMIPercentileRange(
          ageInMonths: chronologicalAgeInMonths,
          gender: gender,
          bmi: bmi,
        );

    final whoBmiPercentileChronoAge = _persentilService
        .getWhoBmiPercentileRange(
          ageInMonths: chronologicalAgeInMonths,
          gender: gender,
          bmi: bmi,
        );

    // Eğer boy yaşı varsa, boy yaşı'na göre de persentiller hesapla
    String neyziWeightPercentileHeightAge = "-";
    String whoWeightPercentileHeightAge = "-";
    String neyzieBmiPercentileHeightAge = "-";
    String whoBmiPercentileHeightAge = "-";

    if (neyziHeightAge > 0) {
      neyziWeightPercentileHeightAge = _persentilService
          .getWeightPercentileRange(
            ageInMonths: neyziHeightAge,
            gender: gender,
            weight: weight,
          );

      neyzieBmiPercentileHeightAge = _persentilService
          .getBMIPercentileRange(
            ageInMonths: neyziHeightAge,
            gender: gender,
            bmi: bmi,
          );
    }

    if (whoHeightAge > 0) {
      whoWeightPercentileHeightAge = _persentilService
          .getWhoWeightPercentileRange(
            ageInMonths: whoHeightAge,
            gender: gender,
            weight: weight,
          );

      whoBmiPercentileHeightAge = _persentilService
          .getWhoBmiPercentileRange(
            ageInMonths: whoHeightAge,
            gender: gender,
            bmi: bmi,
          );
    }

    return PercentileCalculationResult(
      chronologicalAgeInMonths: chronologicalAgeInMonths,
      neyziHeightAgeInMonths: neyziHeightAge,
      whoHeightAgeInMonths: whoHeightAge,
      hasHeightAge: neyziHeightAge > 0 || whoHeightAge > 0,
      // Kronolojik yaş persentilleri
      neyziWeightPercentileChronoAge: neyziWeightPercentileChronoAge,
      whoWeightPercentileChronoAge: whoWeightPercentileChronoAge,
      neyziHeightPercentile: neyziHeightPercentile,
      whoHeightPercentile: whoHeightPercentile,
      neyzieBmiPercentileChronoAge: neyzieBmiPercentileChronoAge,
      whoBmiPercentileChronoAge: whoBmiPercentileChronoAge,
      // Boy yaşı persentilleri
      neyziWeightPercentileHeightAge: neyziWeightPercentileHeightAge,
      whoWeightPercentileHeightAge: whoWeightPercentileHeightAge,
      neyzieBmiPercentileHeightAge: neyzieBmiPercentileHeightAge,
      whoBmiPercentileHeightAge: whoBmiPercentileHeightAge,
      // Boy yaşı durumu
      neyziHeightAgeStatus: neyziHeightAge > 0 
          ? 'Boy Yaşı: ${neyziHeightAge ~/ 12} yıl ${neyziHeightAge % 12} ay'
          : 'Kronolojik Yaş Kullanıldı',
      whoHeightAgeStatus: whoHeightAge > 0 
          ? 'Boy Yaşı: ${whoHeightAge ~/ 12} yıl ${whoHeightAge % 12} ay'
          : 'Kronolojik Yaş Kullanıldı',
    );
  }

  // ===== YAŞ'A GÖRE BOY PERSENTİLİ (BOY YAŞI OLMAYACAK) =====
  String getHeightPercentileByChronologicalAge({
    required int chronologicalAgeInMonths,
    required String gender,
    required double height,
    required String source, // 'neyzi' or 'who'
  }) {
    if (source == 'neyzi') {
      return _persentilService.getHeightPercentileRange(
        ageInMonths: chronologicalAgeInMonths,
        gender: gender,
        height: height,
      );
    } else {
      return _persentilService.getWhoHeightPercentileRange(
        ageInMonths: chronologicalAgeInMonths,
        gender: gender,
        height: height,
      );
    }
  }

  // ===== HELPER: Boy Yaşı Olup Olmadığını Kontrol Et =====
  bool hasHeightAgeCalculated(int neyziHeightAge, int whoHeightAge) {
    return neyziHeightAge > 0 || whoHeightAge > 0;
  }

  // ===== HELPER: Boy Yaşı Metnini Oluştur =====
  String formatHeightAgeDisplay(int neyziHeightAge, int whoHeightAge) {
    if (neyziHeightAge <= 0 && whoHeightAge <= 0) {
      return "-";
    }

    final List<String> parts = [];

    if (neyziHeightAge > 0) {
      final years = (neyziHeightAge / 12).floor();
      final months = neyziHeightAge % 12;
      parts.add("Neyzi: $years yıl $months ay");
    }

    if (whoHeightAge > 0) {
      final years = (whoHeightAge / 12).floor();
      final months = whoHeightAge % 12;
      parts.add("WHO: $years yıl $months ay");
    }

    return parts.join(" | ");
  }
}

// ===== SONUÇ OBJESI =====
class PercentileCalculationResult {
  final int chronologicalAgeInMonths;
  final int neyziHeightAgeInMonths;
  final int whoHeightAgeInMonths;
  final bool hasHeightAge;

  // Kronolojik yaş persentilleri
  final String neyziWeightPercentileChronoAge;
  final String whoWeightPercentileChronoAge;
  final String neyziHeightPercentile;
  final String whoHeightPercentile;
  final String neyzieBmiPercentileChronoAge;
  final String whoBmiPercentileChronoAge;

  // Boy yaşı persentilleri
  final String neyziWeightPercentileHeightAge;
  final String whoWeightPercentileHeightAge;
  final String neyzieBmiPercentileHeightAge;
  final String whoBmiPercentileHeightAge;

  // Boy yaşı durumu
  final String neyziHeightAgeStatus;
  final String whoHeightAgeStatus;

  PercentileCalculationResult({
    required this.chronologicalAgeInMonths,
    required this.neyziHeightAgeInMonths,
    required this.whoHeightAgeInMonths,
    required this.hasHeightAge,
    required this.neyziWeightPercentileChronoAge,
    required this.whoWeightPercentileChronoAge,
    required this.neyziHeightPercentile,
    required this.whoHeightPercentile,
    required this.neyzieBmiPercentileChronoAge,
    required this.whoBmiPercentileChronoAge,
    required this.neyziWeightPercentileHeightAge,
    required this.whoWeightPercentileHeightAge,
    required this.neyzieBmiPercentileHeightAge,
    required this.whoBmiPercentileHeightAge,
    required this.neyziHeightAgeStatus,
    required this.whoHeightAgeStatus,
  });
}
