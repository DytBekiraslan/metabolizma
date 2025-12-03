// lib/viewmodels/metabolizma_viewmodel.dart
import 'dart:async'; 
// import 'dart:io'; // KALDIRILDI
import 'package:flutter/material.dart'; 
import 'package:flutter/services.dart'; 
import 'package:intl/intl.dart';
// import 'package:permission_handler/permission_handler.dart'; // KALDIRILDI
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:file_saver/file_saver.dart'; 
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../models/models.dart';
import '../services/persentil_service_v2.dart'; 
import '../services/persentil_calculator.dart'; 
import 'package:fl_chart/fl_chart.dart'; 
import 'dart:math' show min; 
import 'package:collection/collection.dart'; 
// GÜNCELLEME: open_filex'i 'as open_file' ön eki ile import ediyoruz

// --- HESAPLAMA FONKSİYONLARI (Global Kapsamda Tek Tanım) ---
(double, String, String) calculateBMH_WHO(double weight, int ageInYears, String gender) { 
  if (weight <= 0 || ageInYears < 0) return (0.0, "Geçersiz veri", "Geçersiz veri"); 
  
  double result = 0.0; 
  String formula = ""; 
  String reference = ""; 
  final wStr = weight.toStringAsFixed(2).replaceAll('.', ','); 
  final age = ageInYears; 
  
  if (gender == 'Erkek') { 
    if (age <= 2) { 
      formula = "(60,9 * $wStr) - 54"; 
      result = (60.9 * weight) - 54.0; 
      reference = "Erkek (0-2 Yaş): (60,9 * Ağırlık) - 54.0"; 
    } else if (age <= 10) { 
      formula = "(22.7 * $wStr) + 495"; 
      result = (22.7 * weight) + 495.0; 
      reference = "Erkek (3-10 Yaş): (22.7 * Ağırlık) + 495.0"; 
    } else if (age <= 18) { 
      formula = "(17.5 * $wStr) + 651"; 
      result = (17.5 * weight) + 651.0; 
      reference = "Erkek (11-18 Yaş): (17.5 * Ağırlık) + 651.0"; 
    } else { 
      formula = "(17,5 * $wStr) + 651"; 
      result = (17.5 * weight) + 651.0; 
      reference = "Erkek (19+ Yaş): (17.5 * Ağırlık) + 651.0"; 
    } 
  } else { 
    if (age <= 2) { 
      formula = "(61 * $wStr) - 51"; 
      result = (61 * weight) - 51.0; 
      reference = "Kadın (0-2 Yaş): (61 * Ağırlık) - 51"; 
    } else if (age <= 10) { 
      formula = "(22,5 * $wStr) + 499"; 
      result = (22.5 * weight) + 499.0; 
      reference = "Kadın (3-10 Yaş): (22,5 * Ağırlık) + 499"; 
    } else if (age <= 18) { 
      formula = "(12,2 * $wStr) + 746"; 
      result = (12.2 * weight) + 746; 
      reference = "Kadın (11-18 Yaş): (12,2 * Ağırlık) + 746"; 
    } else { 
      formula = "(12.2 * $wStr) + 746"; 
      result = (12.2 * weight) + 746; 
      reference = "Kadın (19+ Yaş): (12.2 * Ağırlık) + 746"; 
    } 
  } 
  return (result > 0 ? result : 0.0, formula, reference); 
}

(double, String, String) calculateBMI(double weight, double height) { 
  if (weight <= 0 || height <= 0) return (0.0, "Geçersiz veri", "Geçersiz veri"); 
  
  double heightInMeters = height / 100.0; 
  if (heightInMeters == 0) return (0.0, "Boy 0 olamaz", "Boy 0 olamaz"); 
  
  double bmi = weight / (heightInMeters * heightInMeters); 
  final wStr = weight.toStringAsFixed(2).replaceAll('.', ','); 
  final hStr = heightInMeters.toStringAsFixed(2).replaceAll('.', ','); 
  String formula = "$wStr / ($hStr * $hStr)"; 
  String reference = "Ağırlık (kg) / ( Boy(m) * Boy(m) )"; 
  
  return (bmi > 0 ? bmi : 0.0, formula, reference); 
}

double calculateGrowthEnergyAddition(int ageInMonths, double reqFinalWeight) {
  if (reqFinalWeight <= 0) return 0.0;

  if (ageInMonths <= 12) {
    return 20.0 * reqFinalWeight;
  } else if (ageInMonths <= 3 * 12) {
    return 50.0;
  } else if (ageInMonths <= 10 * 12) {
    return 25.0;
  } else {
    return 0.0;
  }
}

({ 
  double protein, 
  String faRange, 
  String enerjiRange, 
  double enerji2, 
  double enerji3, 
  double bge, 
  String proteinFormula, 
  String faFormula, 
  String enerjiFormula, 
  String enerji2Formula, 
  String enerji3Formula, 
  String proteinRef, 
  String faRef, 
  String enerjiRef, 
  String enerji2Ref,
  String enerji3Ref, 
  String proteinConstraint, 
}) calculateRequirements(double ageDouble, int ageInMonths, int ageInYears, double reqFinalWeight, String gender, bool isPregnant, bool isPremature, double bmh, double faf) { 
  
  double proteinKg; 
  String faRange = "-";
  String enerjiRange = "-";
  double proteinMinConstraint = 0.0;
  String proteinConstraint = "-";

  
  if (isPremature || isPregnant) {
    faRange = "Özel Durum (Tablo Dışı)";
    enerjiRange = "Özel Durum (Tablo Dışı)";
  } else if (ageInMonths <= 12) {
    String energyKcalKgRange;
    String faRangeMgKg;
    
    if (ageInMonths == 0) { 
      energyKcalKgRange = "120 (145-95)";
      faRangeMgKg = "25-70 mg/kg";
    } else if (ageInMonths <= 3) {
      energyKcalKgRange = "120 (145-95)";
      faRangeMgKg = "25-70 mg/kg";
    } else if (ageInMonths <= 6) {
      energyKcalKgRange = "120 (145-95)";
      faRangeMgKg = "20-45 mg/kg";
    } else if (ageInMonths <= 9) {
      energyKcalKgRange = "110 (135-80)";
      faRangeMgKg = "15-35 mg/kg";
    } else { 
      energyKcalKgRange = "105 (135-80)";
      faRangeMgKg = "10-35 mg/kg";
    }
    
    final wStr = reqFinalWeight.toStringAsFixed(2).replaceAll('.', ','); 
    
    final minFa = (double.tryParse(faRangeMgKg.split('-')[0].trim()) ?? 0.0) * reqFinalWeight;
    final maxFaPart = faRangeMgKg.split('-')[1].split(' ')[0].trim();
    final maxFa = (double.tryParse(maxFaPart) ?? 0.0) * reqFinalWeight;
    
    faRange = "${minFa.toStringAsFixed(2).replaceAll('.', ',')} - ${maxFa.toStringAsFixed(2).replaceAll('.', ',')} mg ((${faRangeMgKg}) x $wStr kg)"; 
    
    enerjiRange = "$energyKcalKgRange kcal/kg (Kilogram Başına)";
    
    proteinMinConstraint = 0.0; 
    
  } else {
    if (ageInYears <= 4) { 
      faRange = "200 - 400 mg/gün";
      enerjiRange = "1300 (900-1800) kcal/gün";
      proteinMinConstraint = 30.0;
    } else if (ageInYears <= 7) { 
      faRange = "210 - 450 mg/gün";
      enerjiRange = "1700 (1300-2300) kcal/gün";
      proteinMinConstraint = 35.0;
    } else if (ageInYears <= 11) { 
      faRange = "220 - 500 mg/gün";
      enerjiRange = "2400 (1650-3300) kcal/gün";
      proteinMinConstraint = 40.0;
    } else if (gender == 'Kadın') {
      if (ageInYears <= 15) { 
        faRange = "250 - 750 mg/gün";
        enerjiRange = "2200 (1500-3000) kcal/gün";
        proteinMinConstraint = 50.0;
      } else if (ageInYears <= 19) { 
        faRange = "230 - 700 mg/gün";
        enerjiRange = "2100 (1200-3000) kcal/gün";
        proteinMinConstraint = 50.0;
      } else { 
        faRange = "220 - 700 mg/gün";
        enerjiRange = "2100 (1400-2500) kcal/gün";
        proteinMinConstraint = 50.0;
      }
    } else { 
      if (ageInYears <= 15) { 
        faRange = "225 - 900 mg/gün";
        enerjiRange = "2700 (2000-3700) kcal/gün";
        proteinMinConstraint = 55.0;
      } else if (ageInYears <= 19) { 
        faRange = "295 - 1100 mg/gün";
        enerjiRange = "2800 (2100-3900) kcal/gün";
        proteinMinConstraint = 65.0;
      } else { 
        faRange = "290 - 1200 mg/gün";
        enerjiRange = "2900 (2000-3300) kcal/gün";
        proteinMinConstraint = 65.0;
      }
    }
  }
  
  if (ageInMonths <= 12) {
    if (ageInMonths <= 3) proteinKg = 2.5; 
    else if (ageInMonths <= 6) proteinKg = 2.5;
    else proteinKg = 2.4;
  } else {
    if (ageInYears <= 3) proteinKg = 2.0; 
    else if (ageInYears <= 6) proteinKg = 1.7; 
    else if (ageInYears <= 9) proteinKg = 1.6; 
    else proteinKg = 1.5;
  }

  double calculatedProtein = proteinKg * reqFinalWeight; 
  
  if (proteinMinConstraint > 0) {
    if (calculatedProtein >= proteinMinConstraint) {
      proteinConstraint = "'Uygun (\u2265${proteinMinConstraint.toInt()} g)'";
    } else {
      proteinConstraint = "'UYARI: Gereksinimden AZ (\u2265${proteinMinConstraint.toInt()} g)'";
    }
  } else if (isPregnant || isPremature) {
    proteinConstraint = "'Özel Durum Hesaplaması Kullanıldı'";
  } else if (ageInMonths <= 12) {
    proteinConstraint = "'Kilogram Başına Katsayı Kullanıldı'";
  }

  String pFormula = "(${proteinKg.toString().replaceAll('.', ',')} * ${reqFinalWeight.toStringAsFixed(2).replaceAll('.', ',')})"; 
  String pRef = "Eski Tablo Katsayısı: (${proteinKg.toString()} * Ağırlık)";
  
  double enerji2 = 0.0; 
  String enerji2Formula = "-"; 
  String enerji2Ref = "-"; 
  if (ageInMonths <= 12) { 
    enerji2 = 103 * reqFinalWeight; 
    enerji2Ref = "0-12 Ay Pratik: (103-105 * Ağırlık)"; 
    enerji2Formula = "(103 * ${reqFinalWeight.toStringAsFixed(2).replaceAll('.', ',')})"; 
  } else if (ageDouble >= 1.0 && ageDouble <= 10.0) { 
    enerji2 = 1000 + (ageDouble * 100); 
    enerji2Ref = "1-10 Yaş Pratik: 1000 + (Yaş(Yıl) * 100)"; 
    enerji2Formula = "1000 + (${ageDouble.toStringAsFixed(1).replaceAll('.', ',')} * 100)"; 
  }
  
  double bgeValue = calculateGrowthEnergyAddition(ageInMonths, reqFinalWeight);
  double enerji3 = (bmh * faf) + bgeValue;
  
  String bmhStr = bmh.toStringAsFixed(2).replaceAll('.', ',');
  String fafStr = faf.toStringAsFixed(2).replaceAll('.', ',');
  String bgeStr = bgeValue.toStringAsFixed(2).replaceAll('.', ',');
  
  String enerji3Formula = "(${bmhStr} * ${fafStr}) + ${bgeStr}";
  String enerji3Ref = "BMH (WHO) * Fiziksel Aktivite Faktörü (FAF) + Büyüme Gelişme Eki (BGE)";
  
  return ( 
    protein: calculatedProtein > 0 ? calculatedProtein : 0.0, 
    faRange: faRange, 
    enerjiRange: enerjiRange, 
    enerji2: enerji2 > 0 ? enerji2 : 0.0, 
    enerji3: enerji3 > 0 ? enerji3 : 0.0, 
    bge: bgeValue, 
    proteinFormula: pFormula, 
    faFormula: "PKU Tablosundan Aralık",
    enerjiFormula: "PKU Tablosundan Aralık",
    enerji2Formula: enerji2Formula, 
    enerji3Formula: enerji3Formula, 
    proteinRef: pRef, 
    faRef: "PKU Tablosu referans aralığına bakınız. 1 yaş altı kg ile çarpılır.",
    enerjiRef: "PKU Tablosu referans aralığına bakınız. 1 yaş altı kg ile çarpılır.",
    enerji2Ref: enerji2Ref,
    enerji3Ref: enerji3Ref, 
    proteinConstraint: proteinConstraint,
  ); 
}

// YARDIMCI: Yaş hesaplaması için (yıl, ay, gün ve toplam ay cinsinden yaş döndürür)
(int years, int months, int days, double doubleAge) _calculateAge(DateTime? dateOfBirth, [DateTime? visitDate]) {
  if (dateOfBirth == null) return (0, 0, 0, 0.0);
  
  // GÜNCELLEME: Yaş hesaplamasını vizit tarihine göre yap
  // Eğer vizit tarihi belirtilmişse o tarihe göre, yoksa bugüne göre hesapla
  final referenceDate = visitDate ?? DateTime.now();
  
  // Kronolojik yaş hesaplaması (gün, ay, yıl)
  int years = referenceDate.year - dateOfBirth.year;
  int months = referenceDate.month - dateOfBirth.month;
  int days = referenceDate.day - dateOfBirth.day;

  // Ay ve gün düzeltmeleri
  if (days < 0) {
    months--;
    // Geçen ayın gün sayısını bulma (month'u 0 yaparsak önceki ayın son günü döner)
    final lastMonth = DateTime(referenceDate.year, referenceDate.month, 0);
    days += lastMonth.day;
  }
  
  if (months < 0) {
    years--;
    months += 12;
  }

  // Eğer doğum tarihi gelecekten girilmişse sıfırla
  if (years < 0 || (years == 0 && months < 0) || (years == 0 && months == 0 && days < 0)) return (0, 0, 0, 0.0);

  // Toplam ay ve double yaş hesaplaması (hesaplamalar için kullanılır)
  final totalMonths = years * 12 + months;
  final doubleAge = totalMonths / 12.0;

  // YENİ: Düzeltilmiş gün-ay-yıl, toplam ay ve double yaş döndürülür
  return (years, totalMonths, days, doubleAge);
}


enum MealType { sabah, kusluk, ogle, ikindi, aksam, gece }
enum _ScrollDirection { up, down, none }

class CalculatedPercentage {
  final double percentage;
  final Color color;
  final String status;
  final double targetValue; // Hedef değer (kcal, g, mg)
  final double upperLimit; // Üst limit (protein ve FA için)
  final double lowerLimit; // Alt limit (protein ve FA için)

  CalculatedPercentage({
    required this.percentage,
    required this.color,
    required this.status,
    required this.targetValue,
    this.upperLimit = 0.0,
    this.lowerLimit = 0.0,
  });
}

class MetabolizmaViewModel extends ChangeNotifier {
  final PersentilService _persentilService = PersentilService();
  final PersentilCalculator persentilCalculator = PersentilCalculator();

  String? currentRecordId; 
  PatientRecord? currentRecord;
  String loadedPatientName = "";
  
  final TextEditingController nameController = TextEditingController();
  final TextEditingController heightController = TextEditingController();
  final TextEditingController weightController = TextEditingController(); 
  final TextEditingController calculationWeightController = TextEditingController(); 
  CalculatedPercentage energyPercent = CalculatedPercentage(percentage: 0, color: Colors.grey, status: "-", targetValue: 0);
  CalculatedPercentage proteinPercent = CalculatedPercentage(percentage: 0, color: Colors.grey, status: "-", targetValue: 0);
  CalculatedPercentage phePercent = CalculatedPercentage(percentage: 0, color: Colors.grey, status: "-", targetValue: 0);
  
  Map<String, bool> draggableLabelVisibility = {};
  
  DateTime? dateOfBirth;
  final TextEditingController dateOfBirthController = TextEditingController();
  
  String selectedGender = 'Erkek'; 
  bool isPregnant = false; 
  bool isPremature = false;
  
  final TextEditingController fafController = TextEditingController(text: "1.2"); 
  
  WeightSource? selectedWeightSource = WeightSource.current;
  final List<double> percentileOptions = [3, 10, 25, 50, 75, 90, 97];
  double? selectedPercentileValue;
  
  final TextEditingController percentileWeightController = TextEditingController();
  bool isNeyziWeightCardFront = true;
  bool isWhoWeightCardFront = true;
  
  final TextEditingController heightAgeInMonthsDisplayController = TextEditingController();
  int calculatedHeightAgeInMonths = -1; 
  int whoHeightAgeInMonths = -1;

  CalculatedPercentiles calculatedPercentiles = CalculatedPercentiles();
  
  // Getter: Şu anki weight ve height değerlerini al (TextEditingController'lardan)
  double get currentWeight => double.tryParse(weightController.text.replaceAll(',', '.')) ?? 0.0;
  double get currentHeight => double.tryParse(heightController.text.replaceAll(',', '.')) ?? 0.0;
  
  final TextEditingController energyReqController = TextEditingController();
  final TextEditingController proteinReqController = TextEditingController();
  final TextEditingController pheReqController = TextEditingController();
  final TextEditingController bmhController = TextEditingController();
  final TextEditingController bmiController = TextEditingController();
  final TextEditingController energyReq2Controller = TextEditingController();
  final TextEditingController energyReq3Controller = TextEditingController(); 
  // YENİ DOKTOR ORDER ALANLARI
final TextEditingController doctorEnergyController = TextEditingController(); // YENİ: Doktor Order Enerji
final TextEditingController doctorProteinController = TextEditingController(); // YENİ: Doktor Order Protein
final TextEditingController doctorPheController = TextEditingController();     // YENİ: Doktor Order Fenilalanin
bool doctorEnergyCheckbox = false; // Doktor Enerji Hedefi Checkbox
// YENİ DOKTOR ORDER ALANLARI SONU
  
  Map<EnergySource, bool> selectedEnergySources = { 
    EnergySource.doctor: false,
    EnergySource.fku: true, 
    EnergySource.practical: false, 
    EnergySource.bmhFafBge: false,
  };

  String bmhCalculationString = "-"; 
  String bmiCalculationString = "-";
  String enerjiReqCalculationString = "-"; 
  String proteinReqCalculationString = "-";
  String pheReqCalculationString = "-"; 
  String enerjiReq2CalculationString = "-";
  String enerjiReq3CalculationString = "-"; 
  String bmhTooltipString = "-"; 
  String bmiTooltipString = "-";
  String enerjiReqTooltipString = "-"; 
  String proteinReqTooltipString = "-"; 
  String pheReqTooltipString = "-"; 
  String enerjiReq2TooltipString = "-";
  String enerjiReq3TooltipString = "-"; 
  
  final List<ReferenceRequirementFKU> fkuReferenceRequirements = [
    const ReferenceRequirementFKU(ageGroup: 'Yenidoğan (0 ay)', pheRange: '25-70 mg/kg', tyrosineRange: '300-350 mg/kg', proteinRange: '3.50-3.00 g/kg', energyRange: '120 (145-95) kcal/kg', fluidRange: '160-135 mL/kg', index: 0),
    const ReferenceRequirementFKU(ageGroup: '0-3 ay', pheRange: '25-70 mg/kg', tyrosineRange: '300-350 mg/kg', proteinRange: '3.50-3.00 g/kg', energyRange: '120 (145-95) kcal/kg', fluidRange: '160-135 mL/kg', index: 1),
    const ReferenceRequirementFKU(ageGroup: '3-6 ay', pheRange: '20-45 mg/kg', tyrosineRange: '300-350 mg/kg', proteinRange: '3.50-3.00 g/kg', energyRange: '120 (145-95) kcal/kg', fluidRange: '160-130 mL/kg', index: 2),
    const ReferenceRequirementFKU(ageGroup: '6-9 ay', pheRange: '15-35 mg/kg', tyrosineRange: '250-300 mg/kg', proteinRange: '3.00-2.50 g/kg', energyRange: '110 (135-80) kcal/kg', fluidRange: '145-125 mL/kg', index: 3),
    const ReferenceRequirementFKU(ageGroup: '9-12 ay', pheRange: '10-35 mg/kg', tyrosineRange: '250-300 mg/kg', proteinRange: '3.00-2.50 g/kg', energyRange: '105 (135-80) kcal/kg', fluidRange: '135-120 mL/kg', index: 4),

    const ReferenceRequirementFKU(ageGroup: '1-4 yaş', pheRange: '200-400 mg/gün', tyrosineRange: '1.72-3.00 g/gün', proteinRange: '>30 g/gün', energyRange: '1300 (900-1800) kcal/gün', fluidRange: '900-1800 mL/gün', index: 5),
    const ReferenceRequirementFKU(ageGroup: '4-7 yaş', pheRange: '210-450 mg/gün', tyrosineRange: '2.25-3.50 g/gün', proteinRange: '>35 g/gün', energyRange: '1700 (1300-2300) kcal/gün', fluidRange: '1300-2300 mL/gün', index: 6),
    const ReferenceRequirementFKU(ageGroup: '7-11 yaş', pheRange: '220-500 mg/gün', tyrosineRange: '2.55-4.00 g/gün', proteinRange: '>40 g/gün', energyRange: '2400 (1650-3300) kcal/gün', fluidRange: '1650-3300 mL/gün', index: 7),

    const ReferenceRequirementFKU(ageGroup: 'Kadın 11-15 yaş', pheRange: '250-750 mg/gün', tyrosineRange: '3.45-5.00 g/gün', proteinRange: '>50 g/gün', energyRange: '2200 (1500-3000) kcal/gün', fluidRange: '1500-3000 mL/gün', index: 8),
    const ReferenceRequirementFKU(ageGroup: 'Kadın 15-19 yaş', pheRange: '230-700 mg/gün', tyrosineRange: '3.45-5.00 g/gün', proteinRange: '>50 g/gün', energyRange: '2100 (1200-3000) kcal/gün', fluidRange: '1200-3000 mL/gün', index: 9),
    const ReferenceRequirementFKU(ageGroup: 'Kadın >19 yaş', pheRange: '220-700 mg/gün', tyrosineRange: '2.55-4.00 g/gün', proteinRange: '>50 g/gün', energyRange: '2100 (1400-2500) kcal/gün', fluidRange: '2100-2500 mL/gün', index: 10),

    const ReferenceRequirementFKU(ageGroup: 'Erkek 11-15 yaş', pheRange: '225-900 mg/gün', tyrosineRange: '3.38-5.50 g/gün', proteinRange: '>55 g/gün', energyRange: '2700 (2000-3700) kcal/gün', fluidRange: '2000-3700 mL/gün', index: 11),
    const ReferenceRequirementFKU(ageGroup: 'Erkek 15-19 yaş', pheRange: '295-1100 mg/gün', tyrosineRange: '4.42-6.50 g/gün', proteinRange: '>65 g/gün', energyRange: '2800 (2100-3900) kcal/gün', fluidRange: '2100-3900 mL/gün', index: 12),
    const ReferenceRequirementFKU(ageGroup: 'Erkek >19 yaş', pheRange: '290-1200 mg/gün', tyrosineRange: '4.35-6.50 g/gün', proteinRange: '>65 g/gün', energyRange: '2900 (2000-3300) kcal/gün', fluidRange: '2000-3300 mL/gün', index: 13),
  ];
  int highlightedReferenceRowIndex = -1;
  
  final List<({String ageGroup, double proteinKg})> _proteinRequirementTable = const [
    (ageGroup: '0-3 Ay', proteinKg: 2.5),
    (ageGroup: '3-6 Ay', proteinKg: 2.5),
    (ageGroup: '6-12 Ay', proteinKg: 2.4),
    (ageGroup: '1-3 Yaş', proteinKg: 2.0),
    (ageGroup: '4-6 Yaş', proteinKg: 1.7),
    (ageGroup: '7-9 Yaş', proteinKg: 1.6),
    (ageGroup: '9+ Yaş', proteinKg: 1.5),
  ];
  List<({String ageGroup, double proteinKg})> get proteinRequirementTable => _proteinRequirementTable;


  List<FoodRowState> foodRows = List.generate(5, (_) => FoodRowState());
  
  Map<MealType, List<MealEntry>> mealEntries = { for (var v in MealType.values) v: [] };
  List<CustomMealSection> customMealSections = [];
  List<MealPlanItem> mealPlanOrder = [];

  final TextEditingController totalEnergyController = TextEditingController(text: "0.00");
  final TextEditingController totalProteinController = TextEditingController(text: "0.00");
  final TextEditingController totalPheController = TextEditingController(text: "0.00");
  // YENİ FA ALANLARI
final TextEditingController pheLevelController = TextEditingController(); 
  // Getter: Kronolojik yaşı ay olarak döndür
  int get currentAgeInMonths {
    final (_, chronoMonthsTotal, _, __) = _calculateAge(dateOfBirth, visitDate);
    return chronoMonthsTotal;
  }

  DateTime? visitDate = DateTime.now();
final TextEditingController visitDateController = TextEditingController(text: DateFormat('dd.MM.yyyy').format(DateTime.now()));

  // YENİ TİROZİN ALANLARI
final TextEditingController tyrosineLevelController = TextEditingController(); 
DateTime? tyrosineVisitDate = DateTime.now();
final TextEditingController tyrosineVisitDateController = TextEditingController(
    text: DateFormat('dd.MM.yyyy').format(DateTime.now())
);
  
  // YENİ EKLENEN SNAPSHOT ALANLARI
  double _snapshotTotalEnergy = 0.0;
  double _snapshotTotalProtein = 0.0;
  double _snapshotTotalPhe = 0.0;
  bool _isMealAssignmentActive = false;
  // SON SNAPSHOT ALANLARI

  
  List<List<String>>? _pdfBesinTablosuSnapshot;
  String? _pdfTotalsSnapshotEnerji; 
  String? _pdfTotalsSnapshotProtein; 
  String? _pdfTotalsSnapshotFenilalanin;
  bool _isSnapshotTaken = false; 
  
  List<CustomFood> customFoods = []; 
  bool isLoading = true;
  static const String _customFoodsKey = 'customFoods';
  final NumberFormat _numberFormat = NumberFormat("0.00", "tr_TR");
  final NumberFormat _bmiFormat = NumberFormat("0.0", "tr_TR");
  final NumberFormat _reqFormat = NumberFormat("0.0", "tr_TR");
  final NumberFormat _bmhEnerjiFormat = NumberFormat("0.00", "tr_TR");
  final NumberFormat _amountFormat = NumberFormat("0.##", "tr_TR");
  final ScrollController scrollController = ScrollController();
  bool _isDragging = false;
  Timer? _scrollTimer;
  _ScrollDirection _currentScrollDirection = _ScrollDirection.none;
  
  String get calculatedAgeDisplayString {
    // _calculateAge 4 değer döndürür: (years, monthsTotal, days, doubleAge)
    final (years, monthsTotal, days, _) = _calculateAge(dateOfBirth, visitDate); 
    if (dateOfBirth == null || (years == 0 && monthsTotal == 0 && days == 0)) return "-";
    
    final int displayYears = years;
    // monthsTotal değeri zaten toplam ay olduğu için, aylık dilimi hesaplamak için:
    final int displayMonths = monthsTotal % 12; // Modulo ile aylık dilimi al
    final int displayDays = days;
    
    final List<String> parts = [];
    if (displayYears > 0) {
      parts.add("$displayYears Yıl");
    }
    if (displayMonths > 0) {
      parts.add("$displayMonths Ay");
    }
    if (displayDays > 0) {
      parts.add("$displayDays Gün");
    }
    
    if (parts.isEmpty) {
        if (days > 0) {
            return "$days Gün";
        }
        return "-";
    }

    return parts.join(" ");
  }

  MetabolizmaViewModel() { 
    _initializeMealPlanOrder();
    _initialize(); 
  }

  void _initializeMealPlanOrder() {
    mealPlanOrder = MealType.values.map((mealType) {
      return MealPlanItem(
        name: getMealTitle(mealType),
        reference: mealType,
        isCustom: false,
      );
    }).toList();
  }

  Future<void> _initialize() async { 
    isLoading = true; 
    notifyListeners(); 
    await Future.delayed(const Duration(milliseconds: 50)); 
    WidgetsBinding.instance.addPostFrameCallback((_) async { 
      heightController.addListener(_handlePersonalDataChange); 
      weightController.addListener(_handlePersonalDataChange); 
      calculationWeightController.addListener(_handlePersonalDataChange); 
      dateOfBirthController.addListener(_handlePersonalDataChange); 
      fafController.addListener(_handlePersonalDataChange); 
      pheLevelController.addListener(_handlePersonalDataChange);
      visitDateController.addListener(_handlePersonalDataChange);
      tyrosineLevelController.addListener(_handlePersonalDataChange);
      tyrosineVisitDateController.addListener(_handlePersonalDataChange);
      // YENİ EKLENECEK SATIRLAR
      doctorProteinController.addListener(_handlePersonalDataChange); // Yüzdelikleri tetikler
      doctorPheController.addListener(_handlePersonalDataChange);     // Yüzdelikleri tetikler
      for (int i = 0; i < foodRows.length; i++) { 
        _addListenersForRow(i); 
      } 
      await loadCustomFoods(); 
      _initializeCalculations(); 
      isLoading = false; 
      notifyListeners(); 
    }); 
  }
  
  void _addListenersForRow(int index) { 
    if (index < 0 || index >= foodRows.length) return;
    // Her seferinde listener ekle (gereksiz olsa da check yapmaktan daha güvenli)
    foodRows[index].amountController.addListener(_handleAmountChangeForRow); 
    foodRows[index].nameController.addListener(_handleNameChangeForRow);
  }
  
  void _initializeCalculations() { 
    _performAndUpdatePersonalCalculations(notify: false); 
    _recalculateAllRowsAndTotals(notify: false); 
  }
  
  void _handlePersonalDataChange() { 
    _performAndUpdatePersonalCalculations(); 
  }
  
  void _handleAmountChangeForRow() { 
    _recalculateAllRowsAndTotals();
  }
  
  void _handleNameChangeForRow() { 
    _recalculateAllRowsAndTotals(notify: true); 
  }

  @override
  void dispose() {
    heightController.removeListener(_handlePersonalDataChange); 
    weightController.removeListener(_handlePersonalDataChange); 
    calculationWeightController.removeListener(_handlePersonalDataChange); 
    dateOfBirthController.removeListener(_handlePersonalDataChange); 
    fafController.dispose(); 
    for (int i = 0; i < foodRows.length; i++) { 
      foodRows[i].dispose(); 
    }
    nameController.dispose(); 
    heightController.dispose(); 
    weightController.dispose(); 
    calculationWeightController.dispose();
    dateOfBirthController.dispose(); 
    pheLevelController.dispose();
    visitDateController.dispose();
    tyrosineLevelController.dispose();
    tyrosineVisitDateController.dispose();
    energyReqController.dispose(); 
    energyReq2Controller.dispose(); 
    energyReq3Controller.dispose(); 
    proteinReqController.dispose(); 
    pheReqController.dispose(); 
    doctorProteinController.dispose();
    doctorPheController.dispose();
    bmhController.dispose(); 
    bmiController.dispose(); 
    heightAgeInMonthsDisplayController.dispose();
    totalEnergyController.dispose(); 
    totalProteinController.dispose(); 
    totalPheController.dispose();
    _scrollTimer?.cancel();
    scrollController.dispose();
    super.dispose();
  }
  
  void setSelectedEnergySource(EnergySource source, bool? newValue) {
    if (newValue == true) {
      selectedEnergySources.forEach((key, value) {
        selectedEnergySources[key] = key == source;
      });
    } else {
      selectedEnergySources[source] = false;
    }
    _resetPdfSnapshot();
    // Yüzdelerin, seçilen enerji kaynağına göre güncellenmesi için çağrılır
    toplamlariHesapla(); 
  
  }

  void setDateOfBirth(DateTime? newDate) {
    if (newDate != dateOfBirth) {
      dateOfBirth = newDate;
      dateOfBirthController.text = newDate != null ? DateFormat('dd.MM.yyyy').format(newDate) : '';
      _performAndUpdatePersonalCalculations();
      notifyListeners();
    }
  }
  void setVisitDate(DateTime? newDate) {
  if (newDate != visitDate) {
    visitDate = newDate;
    visitDateController.text = newDate != null ? DateFormat('dd.MM.yyyy').format(newDate) : '';
    // Bu sadece görünümü günceller, hesaplamaları tetiklemez
    notifyListeners(); 
  }
  }

  void setTyrosineVisitDate(DateTime? newDate) {
    if (newDate != tyrosineVisitDate) {
      tyrosineVisitDate = newDate;
      tyrosineVisitDateController.text = newDate != null ? DateFormat('dd.MM.yyyy').format(newDate) : '';
      notifyListeners(); 
    }
  }  void setGender(String? newGender) { 
    if (newGender != null && newGender != selectedGender) { 
      selectedGender = newGender; 
      if (selectedGender == 'Erkek' && isPregnant) { 
        isPregnant = false; 
      } 
      _performAndUpdatePersonalCalculations(); 
      notifyListeners(); 
    } 
  }
  
  void setIsPregnant(bool? newValue) { 
    if (newValue != null && newValue != isPregnant) { 
      isPregnant = newValue; 
      if (isPregnant) { 
        selectedGender = 'Kadın'; 
        isPremature = false; 
      } 
      _performAndUpdatePersonalCalculations(); 
      notifyListeners(); 
    } 
  }
  
  void setIsPremature(bool? newValue) { 
    if (newValue != null && newValue != isPremature) { 
      isPremature = newValue; 
      if (isPremature) { 
        isPregnant = false; 
      } 
      _performAndUpdatePersonalCalculations(); 
      notifyListeners(); 
    } 
  }

  void setWeightSource(WeightSource? newSource) {
    if (newSource != null) {
      if (selectedWeightSource == newSource) {
          selectedWeightSource = null; 
          if (newSource != WeightSource.manual) {
              selectedPercentileValue = null;
              percentileWeightController.clear();
          }
      } else {
          selectedWeightSource = newSource;
          if (newSource == WeightSource.whoPercentile || newSource == WeightSource.neyziPercentile) {
              if (selectedPercentileValue == null) {
                  selectedPercentileValue = 50.0;
              }
          }
      }
      
      _performAndUpdatePersonalCalculations();
      notifyListeners();
    }
  }

  void setPercentileValue(double? newValue) {
    if (newValue != null) {
      selectedPercentileValue = newValue;
      notifyListeners(); // Önce UI'ı güncelle
      if (selectedWeightSource == WeightSource.whoPercentile || selectedWeightSource == WeightSource.neyziPercentile) {
          _performAndUpdatePersonalCalculations();
      }
    }
  }

  void setWeightCardFace(PercentileSource source, bool isFront) {
    bool updated = false;
    if (source == PercentileSource.neyzi) {
      if (isNeyziWeightCardFront != isFront) {
        isNeyziWeightCardFront = isFront;
        updated = true;
      }
    } else if (source == PercentileSource.who) {
      if (isWhoWeightCardFront != isFront) {
        isWhoWeightCardFront = isFront;
        updated = true;
      }
    }

    if (!updated) return;

    _performAndUpdatePersonalCalculations(notify: false);
    notifyListeners();
  }

  ({int ageInMonths, bool usedHeightAge}) _resolveAgeForPercentileSource(
      PercentileSource source, int chronoAgeInMonths) {
    final bool wantsHeightAge = source == PercentileSource.neyzi
        ? !isNeyziWeightCardFront
        : !isWhoWeightCardFront;

    final int? heightAgeCandidate = source == PercentileSource.neyzi
        ? (calculatedHeightAgeInMonths > -1 ? calculatedHeightAgeInMonths : null)
        : (whoHeightAgeInMonths > -1 ? whoHeightAgeInMonths : null);

    if (wantsHeightAge && heightAgeCandidate != null) {
      return (ageInMonths: heightAgeCandidate, usedHeightAge: true);
    }

    return (ageInMonths: chronoAgeInMonths, usedHeightAge: false);
  }
  
void _performAndUpdatePersonalCalculations({bool notify = true}) {
    final double currentWeight = double.tryParse(weightController.text.replaceAll(',', '.')) ?? 0.0; 
    final double manualCalcWeight = double.tryParse(calculationWeightController.text.replaceAll(',', '.')) ?? 0.0; 
    final double height = double.tryParse(heightController.text.replaceAll(',', '.')) ?? 0.0;
    
    final (chronoYears, chronoMonthsTotal, chronoDays, _) = _calculateAge(dateOfBirth, visitDate);
    
    final int chronoAgeInYearsForBMH = chronoYears; 
    
    // ===== YENİ: MERKEZI PERSENTIL HESAPLAMASI =====
    final persentilResult = persentilCalculator.calculateAllPercentiles(
      chronologicalAgeInMonths: chronoMonthsTotal,
      gender: selectedGender,
      weight: currentWeight,
      height: height,
    );

    // Boy yaşı değerlerini ViewModel'de sakla
    calculatedHeightAgeInMonths = persentilResult.neyziHeightAgeInMonths;
    whoHeightAgeInMonths = persentilResult.whoHeightAgeInMonths;

    // Boy yaşı display metnini oluştur
    String heightAgeDisplay = "-";
    if (persentilResult.hasHeightAge) {
      heightAgeDisplay =
          persentilCalculator.formatHeightAgeDisplay(persentilResult.neyziHeightAgeInMonths, persentilResult.whoHeightAgeInMonths);
    }
    
    heightAgeInMonthsDisplayController.text = heightAgeDisplay;

    calculatedPercentiles = CalculatedPercentiles(
      neyziWeightPercentile: persentilResult.neyziWeightPercentileChronoAge,
      whoWeightPercentile: persentilResult.whoWeightPercentileChronoAge,
      neyziHeightPercentile: persentilResult.neyziHeightPercentile,
      whoHeightPercentile: persentilResult.whoHeightPercentile,
      neyziBmiPercentile: persentilResult.neyzieBmiPercentileChronoAge,
      whoBmiPercentile: persentilResult.whoBmiPercentileChronoAge,
      neyziHeightAgeStatus: heightAgeDisplay,
      whoHeightAgeStatus: heightAgeDisplay,
    );

    // Burada boy yaşı gösterilmesi için UI'a veri sağlandı
    // ===== YENİ: MERKEZI PERSENTIL HESAPLAMASI SONU =====
    
    final bool hasCalculatedHeightAge = calculatedHeightAgeInMonths != -1;
    final int ageForCalculationsInMonths = hasCalculatedHeightAge
      ? calculatedHeightAgeInMonths
      : chronoMonthsTotal;
    String currentWeightPercentileRange = "-";
    String bmiPercentileRange = "-";
    String heightPercentileRange = "-";

    // Boy yaşı hesaplaması yapılacak _loadCSVPercentilesAndNotify'da
    // Burada sadece boy yaşı için ön hesaplama
    if (height > 0 && chronoMonthsTotal >= 0) {
       // Boy yaşı hesaplaması gerekiyor - CSV yüklendikten sonra yapılacak
       // Şimdilik sadece display'i hazırla
       heightAgeDisplay = "Kronolojik Yaş olarak hesaplandı";
    }
    
    final ageForCalculationsInYears = ageForCalculationsInMonths >= 12
      ? (ageForCalculationsInMonths / 12.0).floor()
      : 0;
    final ageForCalculationsInDouble = ageForCalculationsInMonths / 12.0;

    double reqFinalWeight = 0.0; 
    String weightCalculationSource = "-";
    percentileWeightController.clear(); 
    
    final double bmiCalculationWeight = currentWeight;

    if (selectedWeightSource == WeightSource.manual) {
        reqFinalWeight = manualCalcWeight; 
        weightCalculationSource = "Diyetisyen Tarafından Girilen Ağırlık";
        
        if (reqFinalWeight <= 0) {
           reqFinalWeight = currentWeight; 
           weightCalculationSource = "Kendi Ağırlığı"; // Düzeltildi
        }
    } else if (selectedWeightSource == WeightSource.whoPercentile || selectedWeightSource == WeightSource.neyziPercentile) {
        final source = selectedWeightSource == WeightSource.whoPercentile ? PercentileSource.who : PercentileSource.neyzi;
        
      if (selectedPercentileValue != null && ageForCalculationsInMonths >= 0) {
        final ageLookup =
          _resolveAgeForPercentileSource(source, ageForCalculationsInMonths);
        final double percentileWeight = _persentilService.getPercentileWeight(
          source: source,
          ageInMonths: ageLookup.ageInMonths,
          gender: selectedGender,
          percentileValue: selectedPercentileValue!,
        );
            
            if (percentileWeight > 0) {
                reqFinalWeight = percentileWeight; 
                
                percentileWeightController.text = _amountFormat.format(percentileWeight);
          final sourceLabel =
            source == PercentileSource.neyzi ? 'Neyzi' : 'WHO';
          final ageContext =
            ageLookup.usedHeightAge ? 'Boy Yaşı' : 'Kronolojik Yaş';
          weightCalculationSource =
            "${selectedPercentileValue!.toInt()}. Persentil ($sourceLabel - $ageContext)";
            } else {
                // WHO seçilmişse ve yaş > 10 ay (120 ay), Neyzi seçmeleri gerekiyor mesajını göster
          if (selectedWeightSource == WeightSource.whoPercentile &&
            ageLookup.ageInMonths > 120) {
                    percentileWeightController.text = "Neyzi Persentilini Seçiniz";
                    weightCalculationSource = "Neyzi Persentil Seçim Gerekli";
                    reqFinalWeight = currentWeight; // Fallback olarak kendi ağırlığı
                } else {
                    reqFinalWeight = currentWeight; 
                    weightCalculationSource = "Kendi Ağırlığı)"; // Düzeltildi
                }
            }
        }
    } else if (selectedWeightSource == WeightSource.current) { // YENİ EKLENEN KONTROL
        reqFinalWeight = currentWeight; 
        weightCalculationSource = "Kendi Ağırlığı";
    } else {
        // Eğer hiçbir şey seçili değilse, varsayılan olarak kendi ağırlığına döner (Fallback)
        reqFinalWeight = currentWeight; 
        weightCalculationSource = "Kendi Ağırlığı"; 
    }

    double bmhValue = 0.0;
    
    if (reqFinalWeight > 0 && chronoMonthsTotal >= 0) {
        // YENİ DÜZENLEME: BMH formülü için kronolojik yaş yerine, boy yaşından türetilen yaşı kullan.
        final int ageForBMHCalculation = hasCalculatedHeightAge
          ? ageForCalculationsInYears // Boy yaşı hesaplandıysa onu kullan
          : chronoAgeInYearsForBMH; // Aksi halde kronolojik yaş

        final String ageSource = hasCalculatedHeightAge ? "Boy Yaşı" : "Kronolojik Yaş";

        var (bmh, bmhFormula, bmhRef) = calculateBMH_WHO(reqFinalWeight, ageForBMHCalculation, selectedGender); 
        
        bmhValue = bmh; 
        bmhController.text = _bmhEnerjiFormat.format(bmh); 
        
        bmhCalculationString = "WHO: $bmhFormula = ${bmhController.text} kcal (Yaş Kaynağı: $ageSource (${ageForBMHCalculation} Yıl)) (Ağırlık Kaynağı: $weightCalculationSource)";
        bmhTooltipString = bmhRef;
    } else {
        bmhController.clear();
        bmhCalculationString = "-";
        bmhTooltipString = "-";
    }
    double fafValue = double.tryParse(fafController.text.replaceAll(',', '.')) ?? 1.0;
    fafValue = fafValue.clamp(0.1, 2.0);
    
    if (bmiCalculationWeight > 0 && height > 0 && chronoMonthsTotal >= 0) {
       
       var (bmi, bmiFormula, bmiRef) = calculateBMI(bmiCalculationWeight, height);
       
       bmiPercentileRange = _persentilService.getBMIPercentileRange(
           ageInMonths: chronoMonthsTotal, 
           gender: selectedGender, 
           bmi: bmi
       );
       
       calculatedPercentiles = CalculatedPercentiles(
         weightPercentile: currentWeightPercentileRange, 
         heightPercentile: heightPercentileRange, 
         bmiPercentile: bmiPercentileRange, 
       );
       
       var reqs = calculateRequirements(ageForCalculationsInDouble, ageForCalculationsInMonths, ageForCalculationsInYears, reqFinalWeight, selectedGender, isPregnant, isPremature, bmhValue, fafValue);
       
       bmiController.text = _bmiFormat.format(bmi); 
       bmiCalculationString = "$bmiFormula = ${bmiController.text} (Ağırlık Kaynağı: Kendi Ağırlığı)"; 
       bmiTooltipString = bmiRef;
       
       pheReqController.text = reqs.faRange; 
       energyReqController.text = reqs.enerjiRange; 

       String rawConstraint = reqs.proteinConstraint; 
       if (rawConstraint.startsWith("'") && rawConstraint.endsWith("'")) {
          rawConstraint = rawConstraint.substring(1, rawConstraint.length - 1);
       }
       rawConstraint = rawConstraint.replaceAll('\u2265', '>=');
       
       proteinReqTooltipString = "Protein Katsayıları Tablosuna Göre hesaplanmıştır. | Kısıt Kontrolü: ${rawConstraint}";
       proteinReqController.text = "${_reqFormat.format(reqs.protein)} g (Kontrol: ${rawConstraint})";
       
       enerjiReqCalculationString = "PKU Tablosu Aralık: ${reqs.enerjiRange} (Ağırlık Kaynağı: $weightCalculationSource)"; 
       enerjiReqTooltipString = reqs.enerjiRef;
       
       pheReqCalculationString = "PKU Tablosu Aralık: ${reqs.faRange} (Ağırlık Kaynağı: $weightCalculationSource)"; 
       pheReqTooltipString = reqs.faRef;
       
       proteinReqCalculationString = "${reqs.proteinFormula} = ${_reqFormat.format(reqs.protein)} g (Ağırlık Kaynağı: $weightCalculationSource)"; 

       if (reqs.enerji2 > 0) { 
         energyReq2Controller.text = _bmhEnerjiFormat.format(reqs.enerji2); 
         enerjiReq2CalculationString = "${reqs.enerji2Formula} = ${energyReq2Controller.text} kcal (Ağırlık Kaynağı: $weightCalculationSource)"; 
         enerjiReq2TooltipString = reqs.enerji2Ref; 
       } else { 
         energyReq2Controller.clear(); 
         enerjiReq2CalculationString = "-"; 
         enerjiReq2TooltipString = "-"; 
       }
       
       if (reqs.enerji3 > 0) { 
         energyReq3Controller.text = _bmhEnerjiFormat.format(reqs.enerji3); 
         final bgeStr = reqs.bge > 0 ? "+ ${_bmhEnerjiFormat.format(reqs.bge)} kcal (BGE)" : "";
         enerjiReq3CalculationString = "${reqs.enerji3Formula} = ${energyReq3Controller.text} kcal (FAF=${_bmhEnerjiFormat.format(fafValue)}) $bgeStr (Ağırlık Kaynağı: $weightCalculationSource)"; 
         enerjiReq3TooltipString = reqs.enerji3Ref; 
       } else { 
         energyReq3Controller.clear(); 
         enerjiReq3CalculationString = "-"; 
         enerjiReq3TooltipString = "-"; 
       } 
      
      int newHighlightedIndex = -1; 
      final referenceAgeInMonths = ageForCalculationsInMonths;
      final referenceAgeInYears = ageForCalculationsInYears;

      if (isPremature || isPregnant) {
          newHighlightedIndex = -1; 
      } else if (referenceAgeInMonths == 0) {
          newHighlightedIndex = 0; 
      } else if (referenceAgeInMonths <= 3) {
          newHighlightedIndex = 1; 
      } else if (referenceAgeInMonths <= 6) {
          newHighlightedIndex = 2; 
      } else if (referenceAgeInMonths <= 9) {
          newHighlightedIndex = 3; 
      } else if (referenceAgeInMonths <= 12) {
          newHighlightedIndex = 4; 
      } else {
          final ageInYears = referenceAgeInYears;
          if (ageInYears <= 4) { newHighlightedIndex = 5; } 
          else if (ageInYears <= 7) { newHighlightedIndex = 6; } 
          else if (ageInYears <= 11) { newHighlightedIndex = 7; } 
          else if (selectedGender == 'Kadın') {
              if (ageInYears <= 15) { newHighlightedIndex = 8; } 
              else if (ageInYears <= 19) { newHighlightedIndex = 9; } 
              else { newHighlightedIndex = 10; }
          } else { 
              if (ageInYears <= 15) { newHighlightedIndex = 11; } 
              else if (ageInYears <= 19) { newHighlightedIndex = 12; } 
              else { newHighlightedIndex = 13; }
          }
      }
      highlightedReferenceRowIndex = newHighlightedIndex;
      
      // YENİ GÜNCELLEME: Hesaplanan yeni gereksinimleri doğrudan toplamlariHesapla'ya aktar
      toplamlariHesapla(
        notify: false,
        calculatedEnergy2: reqs.enerji2,
        calculatedEnergy3: reqs.enerji3,
        calculatedProteinReq: reqs.protein,
        pheRangeText: reqs.faRange,
        fkuEnergyRange: reqs.enerjiRange,
      );
      
    } else {
      highlightedReferenceRowIndex = -1; 
      heightAgeInMonthsDisplayController.clear(); 
      calculatedHeightAgeInMonths = -1; 
      percentileWeightController.clear();
      bmhController.clear(); 
      bmiController.clear(); 
      proteinReqController.clear(); 
      pheReqController.clear(); 
      energyReqController.clear(); 
      energyReq2Controller.clear(); 
      energyReq3Controller.clear(); 
      bmhCalculationString = "-"; 
      bmiCalculationString = "-"; 
      proteinReqCalculationString = "-"; 
      pheReqCalculationString = "-"; 
      enerjiReqCalculationString = "-"; 
      enerjiReq2CalculationString = "-"; 
      enerjiReq3CalculationString = "-"; 
      bmhTooltipString = "-"; 
      bmiTooltipString = "-"; 
      proteinReqTooltipString = "-"; 
      pheReqTooltipString = "-"; 
      enerjiReqTooltipString = "-"; 
      enerjiReq2TooltipString = "-";
      enerjiReq3TooltipString = "-"; 
      
      calculatedPercentiles = CalculatedPercentiles();

      // YENİ GÜNCELLEME: Veri yoksa sıfır hedeflerini geç
      toplamlariHesapla(
        notify: false,
        calculatedEnergy2: 0.0,
        calculatedEnergy3: 0.0,
        calculatedProteinReq: 0.0,
        pheRangeText: "-",
        fkuEnergyRange: "-",
      );
    }
    
    // AYRI THREAD'TE: CSV persentillerini async yükle (notifyListeners'i kendisi yapacak)
    if (notify) {
      _loadCSVPercentilesAndNotify(notify: true);
    }
  }

  // CSV persentillerini async yükle ve hesapla
  Future<void> _loadCSVPercentilesAndNotify({bool notify = true}) async {
    final double currentWeight = double.tryParse(weightController.text.replaceAll(',', '.')) ?? 0.0;
    final double height = double.tryParse(heightController.text.replaceAll(',', '.')) ?? 0.0;
    final (chronoYears, chronoMonthsTotal, chronoDays, _) = _calculateAge(dateOfBirth, visitDate);
    
    if (currentWeight <= 0 || height <= 0 || chronoMonthsTotal < 0) {
      if (notify) notifyListeners();
      return;
    }

    calculatedHeightAgeInMonths = -1;
    whoHeightAgeInMonths = -1;

    try {
      // Boy persentili hesaplama - Her zaman kronolojik yaşa göre (çünkü boy yaşı buradan türetilebilir)
      // Neyzi Height Percentile - Use synchronous method
      String neyziHeightPercentile = _persentilService.getHeightPercentileRange(
        ageInMonths: chronoMonthsTotal,
        gender: selectedGender,
        height: height,
      );

      // WHO Height Percentile - Use synchronous method
      String whoHeightPercentile = _persentilService.getWhoHeightPercentileRange(
        ageInMonths: chronoMonthsTotal,
        gender: selectedGender,
        height: height,
      );

      // Boy yaşı hesaplaması (Neyzi < P3 ise)
      String neyziHeightAgeStatus = "Kronolojik Yaş olarak hesaplandı";
      
      print('DEBUG: neyziHeightPercentile = $neyziHeightPercentile');
      print('DEBUG: height = $height, chronoMonthsTotal = $chronoMonthsTotal');
      
      if (neyziHeightPercentile.contains("< P3")) {
        final calculatedAge = _persentilService.getHeightAgeInMonths(
          height: height,
          gender: selectedGender,
          chronologicalAgeInMonths: chronoMonthsTotal,
        );
        
        print('DEBUG: Neyzi calculatedAge = $calculatedAge');
        
        if (calculatedAge != chronoMonthsTotal) {
          calculatedHeightAgeInMonths = calculatedAge;
          
          final heightAgeInYears = calculatedHeightAgeInMonths < 12 ? "0" : (calculatedHeightAgeInMonths / 12.0).toStringAsFixed(1);
          final displayAge = calculatedHeightAgeInMonths < 12 
              ? "${calculatedHeightAgeInMonths} Ay"
              : "$heightAgeInYears Yıl (${calculatedHeightAgeInMonths} Ay)";
          
          neyziHeightAgeStatus = "Boy Yaşı ($displayAge) olarak hesaplandı";
          print('DEBUG: neyziHeightAgeStatus = $neyziHeightAgeStatus');
        }
      }
      
      // Boy yaşı hesaplaması (WHO < P3 ise) - WHO için ayrı hesaplama
      String whoHeightAgeStatus = "Kronolojik Yaş olarak hesaplandı";
      
      print('DEBUG: whoHeightPercentile = $whoHeightPercentile');
      
      if (whoHeightPercentile.contains("< P3")) {
        print('DEBUG: WHO Height < P3, calculating height age');
        final whoCalculatedAge = _persentilService.getWhoHeightAgeInMonths(
          height: height,
          gender: selectedGender,
          chronologicalAgeInMonths: chronoMonthsTotal,
        );
        
        print('DEBUG: WHO calculatedAge = $whoCalculatedAge');
        
        if (whoCalculatedAge != chronoMonthsTotal) {
          final whoHeightAgeInYears = whoCalculatedAge < 12 ? "0" : (whoCalculatedAge / 12.0).toStringAsFixed(1);
          final whoDisplayAge = whoCalculatedAge < 12 
              ? "$whoCalculatedAge Ay"
              : "$whoHeightAgeInYears Yıl ($whoCalculatedAge Ay)";
          
          whoHeightAgeStatus = "Boy Yaşı ($whoDisplayAge) olarak hesaplandı";
          print('DEBUG: whoHeightAgeStatus = $whoHeightAgeStatus');
          whoHeightAgeInMonths = whoCalculatedAge;
        }
      }
      
      heightAgeInMonthsDisplayController.text = neyziHeightAgeStatus;

      // AĞIRLIK VE BKİ PERSENTİLLERİ İÇİN YAŞ BELİRLEME:
      // Boy yaşı hesaplanmışsa (Neyzi < P3), ağırlık ve BKİ için boy yaşını kullan
      // Boy yaşı hesaplanmamışsa, kronolojik yaşı kullan
      final int ageForWeightAndBmi = calculatedHeightAgeInMonths != -1 
          ? calculatedHeightAgeInMonths 
          : chronoMonthsTotal;
          
      print('DEBUG: ageForWeightAndBmi = $ageForWeightAndBmi (calculatedHeightAge: $calculatedHeightAgeInMonths, chronoAge: $chronoMonthsTotal)');
      
      // Neyzi Weight Percentile - Boy yaşına göre (varsa)
      String neyziWeightPercentile = _persentilService.getWeightPercentileRange(
        ageInMonths: ageForWeightAndBmi,
        gender: selectedGender,
        weight: currentWeight,
      );
      print('DEBUG: neyziWeightPercentile = $neyziWeightPercentile');

      // WHO Weight Percentile - Boy yaşına göre (varsa)
      // WHO ağırlık: 10 yaşından (120 aydan) büyükse hesaplama yok
      String whoWeightPercentile = '-';
      if (ageForWeightAndBmi <= 120) {
        whoWeightPercentile = _persentilService.getWhoWeightPercentileRange(
          ageInMonths: ageForWeightAndBmi,
          gender: selectedGender,
          weight: currentWeight,
        );
      }
      print('DEBUG: whoWeightPercentile = $whoWeightPercentile (age: $ageForWeightAndBmi months)');

      // Neyzi BMI Percentile - Boy yaşına göre (varsa)
      double bmi = (currentWeight / ((height / 100) * (height / 100)));
      String neyziBmiPercentile = _persentilService.getBMIPercentileRange(
        ageInMonths: ageForWeightAndBmi,
        gender: selectedGender,
        bmi: bmi,
      );
      print('DEBUG: neyziBmiPercentile = $neyziBmiPercentile, bmi = $bmi');

      // WHO BMI Percentile - Boy yaşına göre (varsa)
      // WHO BMI: 2 yaşından (24 aydan) küçükse hesaplama yok
      String whoBmiPercentile = '-';
      if (ageForWeightAndBmi >= 24) {
        whoBmiPercentile = _persentilService.getWhoBmiPercentileRange(
          ageInMonths: ageForWeightAndBmi,
          gender: selectedGender,
          bmi: bmi,
        );
      }
      print('DEBUG: whoBmiPercentile = $whoBmiPercentile (age: $ageForWeightAndBmi months)');

      // Update CalculatedPercentiles with CSV-based values
      calculatedPercentiles = CalculatedPercentiles(
        weightPercentile: neyziWeightPercentile,
        heightPercentile: neyziHeightPercentile,
        bmiPercentile: neyziBmiPercentile,
        neyziWeightPercentile: neyziWeightPercentile,
        whoWeightPercentile: whoWeightPercentile,
        neyziHeightPercentile: neyziHeightPercentile,
        whoHeightPercentile: whoHeightPercentile,
        neyziBmiPercentile: neyziBmiPercentile,
        whoBmiPercentile: whoBmiPercentile,
        neyziHeightAgeStatus: neyziHeightAgeStatus,
        whoHeightAgeStatus: whoHeightAgeStatus,
      );

      // SADECE BURADA notify et (async işlem bitince)
      if (notify) notifyListeners();
    } catch (e) {
      print('Error loading CSV percentiles: $e');
      if (notify) notifyListeners();
    }
  }

  // Kaydedilmeden önce persentil verilerinin yüklenmesini bekle
  Future<void> ensurePercentileDataLoaded() async {
    final double currentWeight = double.tryParse(weightController.text.replaceAll(',', '.')) ?? 0.0;
    final double height = double.tryParse(heightController.text.replaceAll(',', '.')) ?? 0.0;
    
    print('DEBUG: ensurePercentileDataLoaded çağrıldı - weight=$currentWeight, height=$height');
    print('DEBUG: calculatedPercentiles.neyziWeightPercentile = ${calculatedPercentiles.neyziWeightPercentile}');
    
    if (currentWeight > 0 && height > 0) {
      await _loadCSVPercentilesAndNotify(notify: false);
    }
    
    print('DEBUG: calculatedPercentiles.sonrası = ${calculatedPercentiles.neyziWeightPercentile}');
  }

  void handleDragStarted() { _isDragging = true; _currentScrollDirection = _ScrollDirection.none; _stopScrolling(); }
  void handleDragUpdate(BuildContext context, DragUpdateDetails details) { if (!_isDragging || !scrollController.hasClients) return; final screenHeight = MediaQuery.of(context).size.height; const double edgeThreshold = 80.0; final globalY = details.globalPosition.dy; _ScrollDirection targetDirection = _ScrollDirection.none; if (globalY < edgeThreshold) { targetDirection = _ScrollDirection.up; } else if (globalY > screenHeight - edgeThreshold) { targetDirection = _ScrollDirection.down; } if (targetDirection != _currentScrollDirection) { if (targetDirection == _ScrollDirection.none) { _stopScrolling(); } else { _startScrolling(targetDirection); } } }
  void _startScrolling(_ScrollDirection direction) { _stopScrolling(); _currentScrollDirection = direction; _scrollTimer = Timer.periodic(const Duration(milliseconds: 25), (timer) { if (!_isDragging || !scrollController.hasClients || _currentScrollDirection == _ScrollDirection.none) { _stopScrolling(); return; } const double scrollAmount = 8.0; double newOffset; if (_currentScrollDirection == _ScrollDirection.up) { newOffset = (scrollController.offset - scrollAmount).clamp(0.0, scrollController.position.maxScrollExtent); } else { newOffset = (scrollController.offset + scrollAmount).clamp(0.0, scrollController.position.maxScrollExtent); } if (scrollController.offset != newOffset) { scrollController.jumpTo(newOffset); } else { _stopScrolling(); } }); }
  void _stopScrolling() { if (_scrollTimer != null) { _scrollTimer!.cancel(); _scrollTimer = null; _currentScrollDirection = _ScrollDirection.none; } }
  void handleDragEnd([DragEndDetails? details]) { _isDragging = false; _stopScrolling(); } 

  void addFoodRow() { 
    foodRows.add(FoodRowState()); 
    _addListenersForRow(foodRows.length - 1); 
    notifyListeners(); 
  }

  void addCustomMeal(String name, [int? index]) {
    if (name.trim().isNotEmpty) {
      bool nameExists = MealType.values.any((mt) => getMealTitle(mt).toLowerCase() == name.trim().toLowerCase()) || customMealSections.any((cms) => cms.name.toLowerCase() == name.trim().toLowerCase());
      if (nameExists) { print("Uyarı: '$name' adında bir öğün zaten var."); return; }
      
      final newMeal = CustomMealSection(name.trim());
      
      customMealSections.add(newMeal); 
      
      int insertionIndex = mealPlanOrder.length; 

      if (index != null && index >= 0) {
        insertionIndex = index.clamp(0, mealPlanOrder.length);
      }

      final newItem = MealPlanItem(
        name: name.trim(),
        reference: newMeal,
        isCustom: true,
      );

      mealPlanOrder.insert(insertionIndex, newItem);
      
      _resetPdfSnapshot();
      notifyListeners();
    }
  }
  
  void removeCustomMeal(CustomMealSection meal) {
    if (customMealSections.remove(meal)) {
      mealPlanOrder.removeWhere((item) => item.isCustom && item.reference == meal);
      _resetPdfSnapshot();
      notifyListeners();
    }
  }

  void _recalculateRowAndTotals(int rowIndex) { 
    if (rowIndex < 0 || rowIndex >= foodRows.length) return;
    
    _recalculateRowOnly(rowIndex, shouldUpdateInitial: true); 
    
    toplamlariHesapla(); 
  }
  
  void _recalculateRowOnly(int rowIndex, {bool shouldUpdateInitial = false}) { 
    if (rowIndex < 0 || rowIndex >= foodRows.length) return;
    final row = foodRows[rowIndex];
    
    double currentAmount = double.tryParse(row.amountController.text.replaceAll(',', '.')) ?? 0.0;
    if (currentAmount < 0) currentAmount = 0;
    
    if (row.originalValues != null) {
      double enerjiHesap = row.originalValues!.enerjiDegeri * currentAmount;
      double proteinHesap = row.originalValues!.proteinDegeri * currentAmount;
      double fenilalaninHesap = row.originalValues!.fenilalaninDegeri * currentAmount;
      
      row.energyController.text = _numberFormat.format(enerjiHesap);
      row.proteinController.text = _numberFormat.format(proteinHesap); 
      row.pheController.text = _numberFormat.format(fenilalaninHesap);

      if (shouldUpdateInitial) {
        double totalInitialAmount = currentAmount;
        for (var mealEntries in mealEntries.values) {
          totalInitialAmount += mealEntries
              .where((entry) => entry.sourceRowIndex == rowIndex)
              .fold(0.0, (sum, entry) => sum + entry.assignedAmount);
        }
        for (var customMeal in customMealSections) {
          totalInitialAmount += customMeal.entries
              .where((entry) => entry.sourceRowIndex == rowIndex)
              .fold(0.0, (sum, entry) => sum + entry.assignedAmount);
        }
        
        final initialEnerji = row.originalValues!.enerjiDegeri * totalInitialAmount;
        final initialProtein = row.originalValues!.proteinDegeri * totalInitialAmount;
        final initialPhe = row.originalValues!.fenilalaninDegeri * totalInitialAmount;

        row.initialAmount = totalInitialAmount; 
        row.initialEnergy = initialEnerji; 
        row.initialProtein = initialProtein; 
        row.initialPhe = initialPhe; 
      }
      
    } else { 
      row.clearCalculatedValues();
      row.clearInitialValues(); 
    } 
  }
  
  void _recalculateAllRowsAndTotals({bool notify = true}) { 
    for (int i = 0; i < foodRows.length; i++) { 
      _recalculateRowOnly(i, shouldUpdateInitial: true); 
    } 
    toplamlariHesapla(notify: notify); 
  }
  
  void toplamlariHesapla({
    bool notify = true,
    double? calculatedEnergy2, 
    double? calculatedEnergy3,
    double? calculatedProteinReq,
    String? pheRangeText,
    String? fkuEnergyRange,
  }) { 
    double toplamEnerji = 0; 
    double toplamProtein = 0; 
    double toplamFenilalanin = 0; 
    
    for (var row in foodRows) { 
      toplamEnerji += double.tryParse(row.energyController.text.replaceAll(',', '.')) ?? 0.0; 
      toplamProtein += double.tryParse(row.proteinController.text.replaceAll(',', '.')) ?? 0.0; 
      toplamFenilalanin += double.tryParse(row.pheController.text.replaceAll(',', '.')) ?? 0.0; 
    } 
    
    // YENİ KONTROL: Öğün ataması aktif ise, yüzdelik hesaplaması için snapshot kullan.
    if (_isMealAssignmentActive) {
        if (_snapshotTotalEnergy == 0 && _snapshotTotalProtein == 0 && _snapshotTotalPhe == 0) {
            _snapshotTotalEnergy = foodRows.fold(0.0, (sum, row) => sum + row.initialEnergy);
            _snapshotTotalProtein = foodRows.fold(0.0, (sum, row) => sum + row.initialProtein);
            _snapshotTotalPhe = foodRows.fold(0.0, (sum, row) => sum + row.initialPhe);
        }
    } else {
        _snapshotTotalEnergy = 0.0;
        _snapshotTotalProtein = 0.0;
        _snapshotTotalPhe = 0.0;
    }
    
    // ✅ DÜZELTME: Doğru değişkenler kullanılıyor
    final double finalTotalEnergy = _isMealAssignmentActive ? _snapshotTotalEnergy : toplamEnerji;
    final double finalTotalProtein = _isMealAssignmentActive ? _snapshotTotalProtein : toplamProtein;
    final double finalTotalPhe = _isMealAssignmentActive ? _snapshotTotalPhe : toplamFenilalanin;

    // Toplam Controller'ları güncelle
    totalEnergyController.text = _numberFormat.format(toplamEnerji); 
    totalProteinController.text = _numberFormat.format(toplamProtein); 
    totalPheController.text = _numberFormat.format(toplamFenilalanin); 
    
    // ✅ DÜZELTME: Doğru parametrelerle çağırıldı
    _calculateAllPercentages(
      finalTotalEnergy, 
      finalTotalProtein, 
      finalTotalPhe, 
      calculatedEnergy2: calculatedEnergy2,
      calculatedEnergy3: calculatedEnergy3,
      calculatedProteinReq: calculatedProteinReq,
      pheRangeText: pheRangeText,
      fkuEnergyRange: fkuEnergyRange,
    );
    
    if (notify) notifyListeners();
  }
  // YENİ METOT: Yüzdelik Hesaplamaları Yapar
  void _calculateAllPercentages(double totalEnergy, double totalProtein, double totalPhe, {
      double? calculatedEnergy2, 
      double? calculatedEnergy3,
      double? calculatedProteinReq,
      String? pheRangeText,
      String? fkuEnergyRange,
  }) {
    // 1. Enerji Gereksinimini Belirle (Seçili Kaynağa Göre)
    double requiredEnergy = 0.0;
    
    // Geçerli hesaplanmış değerleri kullan veya Controller'lardan oku (Fallback)
    final double energy3 = calculatedEnergy3 ?? double.tryParse(energyReq3Controller.text.replaceAll(',', '.')) ?? 0.0;
    final double energy2 = calculatedEnergy2 ?? double.tryParse(energyReq2Controller.text.replaceAll(',', '.')) ?? 0.0;
    
    if (selectedEnergySources[EnergySource.doctor] == true) {
      // Doktor Hedefi seçildi
      requiredEnergy = double.tryParse(doctorEnergyController.text.replaceAll(',', '.')) ?? 0.0;
    } else if (selectedEnergySources[EnergySource.fku] == true) {
      // FKÜ'den gelen aralığın orta veya minimum değerini hedef almalıyız.
      // Basitlik için sadece Enerji (BMH*FAF+BGE) değerini hedef alıyorum
      // çünkü bu, hesaplanan tekil bir değerdir.
      requiredEnergy = energy3;
      if (requiredEnergy == 0.0) {
        requiredEnergy = energy2;
      }
    } else if (selectedEnergySources[EnergySource.practical] == true) {
       requiredEnergy = energy2;
    } else if (selectedEnergySources[EnergySource.bmhFafBge] == true) {
       requiredEnergy = energy3;
    }
    
    // Fallback: Eğer hiçbir hesaplanan tekil değer yoksa, FKÜ aralığını parse etmeye çalış (min değerini al)
    if (requiredEnergy == 0.0) {
        // Hedefi Controller'dan oku (veya parametre kullan)
        final String rangeText = fkuEnergyRange ?? energyReqController.text;

        if (rangeText.contains('-')) {
            final parts = rangeText.split('(');
            if (parts.length > 1) {
                final range = parts[1].split(')')[0].replaceAll(' ', '');
                requiredEnergy = double.tryParse(range.split('-').first) ?? 0.0;
            }
        }
    }
    
    // 2. Protein Gereksinimini Belirle (Hesaplanan Değer)
    double requiredProtein;
    String proteinTargetSource = "Hesaplanan";

    // YENİ KONTROL: DOKTOR ORDER'INI KULLAN
    final double doctorProtein = double.tryParse(doctorProteinController.text.replaceAll(',', '.')) ?? 0.0;
    
    if (doctorProtein > 0) {
        requiredProtein = doctorProtein;
        proteinTargetSource = "";
    } else if (calculatedProteinReq != null) {
      requiredProtein = calculatedProteinReq;
    } else {
      // Hedefi Controller'dan oku (Fallback)
      requiredProtein = double.tryParse(proteinReqController.text.split(' ')[0].replaceAll(',', '.')) ?? 0.0;
    }
    
    /// 3. Fenilalanin Gereksinimini Belirle (Aralık)
    double pheLower = 0.0;
    double pheUpper = 0.0;
    String pheTargetSource = "PKU Tablosu";

    // YENİ KONTROL: DOKTOR ORDER'INI KULLAN
    final double doctorPhe = double.tryParse(doctorPheController.text.replaceAll(',', '.')) ?? 0.0;

    if (doctorPhe > 0) {
        // Eğer doktor tek bir FA değeri girdiyse, bu değeri hem alt hem üst hedef olarak al.
        pheLower = doctorPhe;
        pheUpper = doctorPhe;
        pheTargetSource = "";
    } else {
        final String targetPheRangeText = pheRangeText ?? pheReqController.text;

        if (targetPheRangeText.contains('-')) {
            final parts = targetPheRangeText.replaceAll(RegExp(r'[^\d,-]'), '').split('-');
            if (parts.length >= 2) {
                               pheLower = double.tryParse(parts[0].replaceAll(',', '.')) ?? 0.0;
                pheUpper = double.tryParse(parts[1].replaceAll(',', '.')) ?? 0.0;
            }
        }
    }
    // --- Enerji Yüzdesi Hesaplama ---
    if (requiredEnergy > 0) {
        final percentage = min(100.0, (totalEnergy / requiredEnergy) * 100);
        Color color;
        String status;
        
        if (totalEnergy < requiredEnergy * 0.95) { // %5 altı sapma kabul edilebilir
            color = const Color.fromARGB(255, 238, 255, 0); // Sarı (Altında)
            status = "Enerji Gereksinimi Altında";
        } else if (totalEnergy > requiredEnergy * 1.05) { // %5 üstü sapma kabul edilebilir
            color = Colors.red; // Kırmızı (Üstünde)
            status = "Enerji Gereksinimini Aşıyor";
        } else {
            color = Colors.green; // Yeşil (Aralıkta)
            status = "Enerji Gereksinimi Karşılandı";
        }
        
        energyPercent = CalculatedPercentage(
            percentage: percentage, 
            color: color, 
            status: status, 
            targetValue: requiredEnergy
        );
    } else {
        energyPercent = CalculatedPercentage(percentage: 0, color: Colors.grey, status: "Hedef Enerji Tanımlanmadı", targetValue: 0);
    }
    
    // --- Protein Yüzdesi Hesaplama ---
    if (requiredProtein > 0) {
        const double tolerance = 2.0; // +/- 2 gram tolerans
        final proteinMin = requiredProtein - tolerance;
        final proteinMax = requiredProtein + tolerance;
        
        final percentage = (totalProtein / requiredProtein) * 100;
        Color color;
        String status;
        
        if (totalProtein < proteinMin) {
           color = const Color.fromARGB(255, 238, 255, 0); // Sarı (Çok Altında)
            status = "Protein Gereksinimi Altında (<-${tolerance.toInt()}g)";
        } else if (totalProtein > proteinMax) {
            color = Colors.red; // Kırmızı (Çok Üstünde)
            status = "Protein Gereksinimini Aşıyor (>+${tolerance.toInt()}g)";
        } else {
            color = Colors.green; // Yeşil (Aralıkta)
            status = "Protein Hedefi +/-(${tolerance.toInt()}g) Karşılandı";
        }
        
       proteinPercent = CalculatedPercentage(
            percentage: min(100.0, percentage), 
            color: color, 
            status: "$proteinTargetSource ($status)", // Kaynak bilgisini ekle
            targetValue: requiredProtein,
            lowerLimit: proteinMin,
            upperLimit: proteinMax
        );
    } else {
        proteinPercent = CalculatedPercentage(percentage: 0, color: Colors.grey, status: "Protein Hedefi Tanımlanmadı", targetValue: 0);
    }
    
    // --- Fenilalanin (FA) Yüzdesi Hesaplama ---
    if (pheUpper > 0 && pheLower >= 0) {
        final percentage = (totalPhe / pheUpper) * 100;
        Color color;
        String status;

        if (totalPhe < pheLower) {
           color = const Color.fromARGB(255, 179, 190, 25); // Sarı (Altında)
            status = "FA Gereksinim Aralığı Altında";
        } else if (totalPhe > pheUpper) {
            color = Colors.red; // Kırmızı (Üstünde)
            status = "FA Gereksinim Aralığını Aşıyor";
        } else {
            color = Colors.green; // Yeşil (Aralıkta)
            status = "FA Gereksinim Aralığı İçinde";
        }

        // Bar gösterimi için hedefi üst limit alabiliriz.
      phePercent = CalculatedPercentage(
            percentage: min(100.0, percentage), 
            color: color, 
            status: "$pheTargetSource ($status)", // Kaynak bilgisini ekle
            targetValue: pheUpper,
            lowerLimit: pheLower,
            upperLimit: pheUpper
        );
    } else {
        phePercent = CalculatedPercentage(percentage: 0, color: Colors.grey, status: "FA Aralığı Tanımlanmadı", targetValue: 0);
    }
}
  void setDraggableLabelVisibility(String labelName, bool isVisible) { if (draggableLabelVisibility[labelName] != isVisible) { draggableLabelVisibility[labelName] = isVisible; notifyListeners(); } }
  
  void satiriTemizle(int rowIndex) { 
    if (rowIndex < 0 || rowIndex >= foodRows.length) return;
    final row = foodRows[rowIndex];
    
    String? labelNameToRestore = row.originalLabelName;
    
    row.clear();
    
    if (labelNameToRestore != null) { 
      setDraggableLabelVisibility(labelNameToRestore, true); 
    } 
    
    _resetPdfSnapshot(); 
    _recalculateRowAndTotals(rowIndex); 
  }
  
  Future<String?> _showAmountDialog(BuildContext context, String foodName, double? maxAmount) async { final amountController = TextEditingController(); final formKey = GlobalKey<FormState>(); return await showDialog<String>( context: context, barrierDismissible: false, builder: (BuildContext dialogContext) { return AlertDialog( title: Text('"$foodName" için Miktar Girin'), content: Form( key: formKey, child: TextFormField( controller: amountController, 
  keyboardType: const TextInputType.numberWithOptions(decimal: true), 
  inputFormatters: [ FilteringTextInputFormatter.allow(RegExp(r'^\d*[,.]?\d*')), ], 
  autofocus: true, decoration: InputDecoration( hintText: maxAmount != null ? 'Miktar (Maks: ${_amountFormat.format(maxAmount)})' : 'Miktar', border: const OutlineInputBorder(), ), validator: (value) { if (value == null || value.isEmpty) { return 'Lütfen bir miktar girin.'; } final enteredAmount = double.tryParse(value.replaceAll(',', '.')) ?? -1.0; if (enteredAmount <= 0) { return 'Geçerli bir miktar girin (> 0).'; } if (maxAmount != null && enteredAmount > maxAmount) { return 'Miktar, mevcut miktardan fazla olamaz (${_amountFormat.format(maxAmount)}).'; } return null; }, ), ), actions: <Widget>[ TextButton(child: const Text('İptal'), onPressed: () => Navigator.of(dialogContext).pop(null)), ElevatedButton(child: const Text('Ekle'), onPressed: () { if (formKey.currentState!.validate()) { Navigator.of(dialogContext).pop(amountController.text); } }), ], ); }, ); }
  
  Future<void> handleLabelDropOnFoodRow({ required BuildContext context, required DraggableFoodData data, required int targetRowIndex, }) async { 
    if (targetRowIndex < 0 || targetRowIndex >= foodRows.length) return;
    final targetRow = foodRows[targetRowIndex];
    final enteredAmountStr = await _showAmountDialog(context, data.displayName, null);
    
    if (enteredAmountStr != null && enteredAmountStr.isNotEmpty) {
      final enteredAmount = double.tryParse(enteredAmountStr.replaceAll(',', '.')) ?? 0.0;
      
      if (enteredAmount > 0) {
        if(targetRow.originalLabelName != null && targetRow.originalLabelName != data.labelName) { 
          setDraggableLabelVisibility(targetRow.originalLabelName!, true); 
        }
        
        targetRow.originalValues = data.baseValues;
        targetRow.originalLabelName = data.labelName;
        targetRow.nameController.text = data.displayName;
        _addListenersForRow(targetRowIndex);
        
        targetRow.amountController.text = _amountFormat.format(enteredAmount);
        
        setDraggableLabelVisibility(data.labelName, false); 
        
        targetRow.initialAmount = enteredAmount; 
        targetRow.initialEnergy = data.baseValues.enerjiDegeri * enteredAmount; 
        targetRow.initialProtein = data.baseValues.proteinDegeri * enteredAmount; 
        targetRow.initialPhe = data.baseValues.fenilalaninDegeri * enteredAmount; 
        
        _resetPdfSnapshot();
        _recalculateRowAndTotals(targetRowIndex); 
        notifyListeners(); 
      } else { 
        ScaffoldMessenger.of(context).showSnackBar( 
          SnackBar(content: Text('Geçersiz miktar girildi: $enteredAmountStr'), backgroundColor: Colors.red),
        ); 
      } 
    } 
  }
  
  Future<void> assignFoodToMeal({ required BuildContext context, required int sourceRowIndex, required MealType targetMeal, }) async { 
    if (sourceRowIndex < 0 || sourceRowIndex >= foodRows.length) return;
    final sourceRow = foodRows[sourceRowIndex];
    
    final currentAmount = double.tryParse(sourceRow.amountController.text.replaceAll(',', '.')) ?? 0.0;
    final foodName = sourceRow.nameController.text;

    if (currentAmount <= 0.001 || foodName.isEmpty) { 
      ScaffoldMessenger.of(context).showSnackBar( 
        const SnackBar(content: Text('Kaynak satırda atanacak miktar veya besin adı yok.'), backgroundColor: Colors.orange),
      );
      return;
    }

    final assignedAmountStr = await _showAmountDialog(context, foodName, currentAmount);
    
    if (assignedAmountStr != null && assignedAmountStr.isNotEmpty) {
      final assignedAmount = double.tryParse(assignedAmountStr.replaceAll(',', '.')) ?? 0.0;
      
      if (assignedAmount > 0 && assignedAmount <= currentAmount) {
        
        // YENİ EKLENEN SATIR: Öğün atama sürecini başlat
        _isMealAssignmentActive = true; 

        if (!_isSnapshotTaken) {
          _takePdfBesinTablosuSnapshot();
          _isSnapshotTaken = true;
        }

        final newEntry = MealEntry( 
          sourceRowIndex: sourceRowIndex, 
          foodName: foodName, 
          assignedAmount: assignedAmount
        );
        
        mealEntries[targetMeal]?.add(newEntry);
        
        final newSourceAmount = currentAmount - assignedAmount;
        
        if (newSourceAmount <= 0.001) { 
          sourceRow.amountController.text = "0"; 
          sourceRow.clearCalculatedValues();
        } else {
          sourceRow.amountController.text = _amountFormat.format(newSourceAmount);
        }
        
        _recalculateRowOnly(sourceRowIndex); 
        toplamlariHesapla();
        
        // Başarılı atama sonrası bayrağı kapat ve yeniden hesapla
        _isMealAssignmentActive = false; 

        notifyListeners();
      }
    } 
    // Bayrak, diyalog iptal edilse bile false olarak ayarlanır
    _isMealAssignmentActive = false;
  }
  
  Future<void> assignFoodToCustomMeal({ required BuildContext context, required int sourceRowIndex, required CustomMealSection targetCustomMeal, }) async { 
    if (sourceRowIndex < 0 || sourceRowIndex >= foodRows.length) return;
    final sourceRow = foodRows[sourceRowIndex];
    
    final currentAmount = double.tryParse(sourceRow.amountController.text.replaceAll(',', '.')) ?? 0.0;
    final foodName = sourceRow.nameController.text;

    if (currentAmount <= 0.001 || foodName.isEmpty) { 
      ScaffoldMessenger.of(context).showSnackBar( 
        const SnackBar(content: Text('Kaynak satırda atanacak miktar veya besin adı yok.'), backgroundColor: Colors.orange),
      );
      return;
    }

    final assignedAmountStr = await _showAmountDialog(context, foodName, currentAmount);
    
    if (assignedAmountStr != null && assignedAmountStr.isNotEmpty) {
      final assignedAmount = double.tryParse(assignedAmountStr.replaceAll(',', '.')) ?? 0.0;
      
      if (assignedAmount > 0 && assignedAmount <= currentAmount) {
        
        // YENİ EKLENEN SATIR: Öğün atama sürecini başlat
        _isMealAssignmentActive = true;

        if (!_isSnapshotTaken) {
          _takePdfBesinTablosuSnapshot();
          _isSnapshotTaken = true;
        }

        final newEntry = MealEntry( 
          sourceRowIndex: sourceRowIndex, 
          foodName: foodName, 
          assignedAmount: assignedAmount
        );
        
        targetCustomMeal.entries.add(newEntry);
        
        final newSourceAmount = currentAmount - assignedAmount;
        
        if (newSourceAmount <= 0.001) { 
          sourceRow.amountController.text = "0"; 
          sourceRow.clearCalculatedValues();
        } else {
          sourceRow.amountController.text = _amountFormat.format(newSourceAmount);
        }
        
        _recalculateRowOnly(sourceRowIndex); 
        toplamlariHesapla();
        
        // Başarılı atama sonrası bayrağı kapat ve yeniden hesapla
        _isMealAssignmentActive = false; 

        notifyListeners();
      }
    }
    // Bayrak, diyalog iptal edilse bile false olarak ayarlanır
    _isMealAssignmentActive = false;
  }

  void removeFoodFromCustomMeal({ required CustomMealSection customMeal, required int entryIndex, }) { 
    if (entryIndex >= 0 && entryIndex < customMeal.entries.length) {
      final removedEntry = customMeal.entries.removeAt(entryIndex);
      
      if (removedEntry.sourceRowIndex >= 0 && removedEntry.sourceRowIndex < foodRows.length) {
        final sourceRow = foodRows[removedEntry.sourceRowIndex];
        
        if (sourceRow.originalValues != null) { 
          final currentSourceAmount = double.tryParse(sourceRow.amountController.text.replaceAll(',', '.')) ?? 0.0;
          final newSourceAmount = currentSourceAmount + removedEntry.assignedAmount;
          
          sourceRow.amountController.text = _amountFormat.format(newSourceAmount);
          
          if (sourceRow.originalLabelName != null) {
            setDraggableLabelVisibility(sourceRow.originalLabelName!, true);
          }
        } else { 
          final currentSourceAmount = double.tryParse(sourceRow.amountController.text.replaceAll(',', '.')) ?? 0.0;
          final newSourceAmount = currentSourceAmount + removedEntry.assignedAmount;
          sourceRow.amountController.text = _amountFormat.format(newSourceAmount);
        }
        
        _recalculateRowOnly(removedEntry.sourceRowIndex); 
        toplamlariHesapla();
      } else { 
        print("Uyarı: Öğün girdisi silindi ancak kaynak satır (${removedEntry.sourceRowIndex}) bulunamadı veya değişmiş."); 
      }
      notifyListeners();
    } 
  }
  
  void removeFoodFromMeal({ required MealType meal, required int entryIndex, }) { 
    if (mealEntries.containsKey(meal) && entryIndex >= 0 && entryIndex < mealEntries[meal]!.length) {
      final removedEntry = mealEntries[meal]!.removeAt(entryIndex);
      
      if (removedEntry.sourceRowIndex >= 0 && removedEntry.sourceRowIndex < foodRows.length) {
        final sourceRow = foodRows[removedEntry.sourceRowIndex];
        
        if (sourceRow.originalValues != null) { 
          final currentSourceAmount = double.tryParse(sourceRow.amountController.text.replaceAll(',', '.')) ?? 0.0;
          final newSourceAmount = currentSourceAmount + removedEntry.assignedAmount;
          
          sourceRow.amountController.text = _amountFormat.format(newSourceAmount);
          
          if (sourceRow.originalLabelName != null) {
            setDraggableLabelVisibility(sourceRow.originalLabelName!, true);
          }
        } else { 
          final currentSourceAmount = double.tryParse(sourceRow.amountController.text.replaceAll(',', '.')) ?? 0.0;
          final newSourceAmount = currentSourceAmount + removedEntry.assignedAmount;
          sourceRow.amountController.text = _amountFormat.format(newSourceAmount);
        }
        
        _recalculateRowOnly(removedEntry.sourceRowIndex); 
        toplamlariHesapla();
      } else { 
        print("Uyarı: Öğün girdisi silindi ancak kaynak satır (${removedEntry.sourceRowIndex}) bulunamadı veya değişmiş."); 
      }
      notifyListeners();
    } 
  }
  
  void _takePdfBesinTablosuSnapshot() { 
    print("--- PDF için Besin Tablosu ve Toplam Anlık Görüntüsü Alınıyor ---");
    List<List<String>> snapshotData = []; 
    double totalSnapshotEnergy = 0;
    double totalSnapshotProtein = 0;
    double totalSnapshotPhe = 0;
    
    for(int i=0; i<foodRows.length; i++){
      final rowState = foodRows[i];
      String ad = rowState.nameController.text;
      
      bool isValidFoodEntry = ad.trim().isNotEmpty && rowState.originalValues != null;
      
      if (isValidFoodEntry) {
        final amountStr = _amountFormat.format(rowState.initialAmount);
        final enerjiStr = _numberFormat.format(rowState.initialEnergy);
        final proteinStr = _numberFormat.format(rowState.initialProtein);
        final faStr = _numberFormat.format(rowState.initialPhe);
        
        snapshotData.add([ad, amountStr, enerjiStr, proteinStr, faStr]);
        
        totalSnapshotEnergy += rowState.initialEnergy;
        totalSnapshotProtein += rowState.initialProtein;
        totalSnapshotPhe += rowState.initialPhe;
      }
    } 
    
    _pdfTotalsSnapshotEnerji = _numberFormat.format(totalSnapshotEnergy);
    _pdfTotalsSnapshotProtein = _numberFormat.format(totalSnapshotProtein);
    _pdfTotalsSnapshotFenilalanin = _numberFormat.format(totalSnapshotPhe);
    _pdfBesinTablosuSnapshot = snapshotData; 
    
    print("--- Anlık Görüntü Alındı. Toplam ${snapshotData.length} anlamlı satır. ---");
  }

  void _resetPdfSnapshot() { _pdfBesinTablosuSnapshot = null; _pdfTotalsSnapshotEnerji = null; _pdfTotalsSnapshotProtein = null; _pdfTotalsSnapshotFenilalanin = null; _isSnapshotTaken = false; print("PDF Snapshot sıfırlandı."); }
  
  Future<void> loadCustomFoods() async { 
    try { 
      final prefs = await SharedPreferences.getInstance(); 
      final String? storedFoodsString = prefs.getString(_customFoodsKey); 
      
      if (storedFoodsString != null && storedFoodsString.isNotEmpty) { 
        customFoods = CustomFood.decode(storedFoodsString); 
        if (!customFoods.any((food) => food.isDefault && food.name.toLowerCase() == 'ekmek')) {
             customFoods.insert(0, CustomFood(name: 'Ekmek', protein: 1.0, fa: 50.0, enerji: 34.0, isDefault: true));
        }
        if (!customFoods.any((food) => food.isDefault && food.name.toLowerCase() == 'pku jel')) {
             customFoods.insert(0, CustomFood(name: 'PKU Jel', protein: 10.0, fa: 0.0, enerji: 81.0, isDefault: true));
        }
        await _saveCustomFoods();
      } else { 
        customFoods = [ 
          CustomFood(name: 'Ekmek', protein: 1.0, fa: 50.0, enerji: 34.0, isDefault: true), 
          CustomFood(name: 'PKU Jel', protein: 10.0, fa: 0.0, enerji: 81.0, isDefault: true), 
        ]; 
        await _saveCustomFoods(); 
      } 
      
      draggableLabelVisibility.clear(); 
      for (var food in customFoods) { 
        draggableLabelVisibility["custom_${food.name}"] = true; 
      } 
    } catch (e) { 
      print("HATA: Özel besinler yüklenemedi: $e"); 
      customFoods = []; 
    } 
  }
  
  Future<void> _saveCustomFoods() async { 
    try { 
      final prefs = await SharedPreferences.getInstance(); 
      final String foodsString = CustomFood.encode(customFoods); 
      await prefs.setString(_customFoodsKey, foodsString); 
    } catch (e) { 
      print("HATA: Özel besinler kaydedilemedi: $e"); 
    } 
  }
  
  Future<void> addNewCustomFood({ required String name, required double protein, required double fa, required double enerji, }) async { 
    if (name.trim().isEmpty) { 
      throw Exception("Besin adı boş olamaz."); 
    } 
    final lowerCaseName = name.trim().toLowerCase(); 
    if (customFoods.any((food) => food.name.toLowerCase() == lowerCaseName)) { 
      throw Exception("'$name' adında bir besin zaten var."); 
    } 
    final newFood = CustomFood( 
      name: name.trim(), 
      protein: protein, 
      fa: fa, 
      enerji: enerji, 
      isDefault: false 
    ); 
    customFoods.add(newFood); 
    draggableLabelVisibility["custom_${newFood.name}"] = true; 
    await _saveCustomFoods(); 
    notifyListeners(); 
  }
  
  Future<void> updateCustomFood({ required int index, required String name, required double protein, required double fa, required double enerji, }) async { 
    if (index < 0 || index >= customFoods.length) { 
      throw Exception("Güncellenecek besin bulunamadı (index: $index)."); 
    } 
    final originalFood = customFoods[index]; 
    final newName = name.trim(); 
    final lowerCaseName = newName.toLowerCase(); 
    
    if (originalFood.name.toLowerCase() != lowerCaseName) { 
      bool nameExists = false; 
      for (int i = 0; i < customFoods.length; i++) { 
        if (i != index && customFoods[i].name.toLowerCase() == lowerCaseName) { 
          nameExists = true; 
          break; 
        } 
      } 
      if (nameExists) { 
        throw Exception("'$newName' adında bir besin zaten var."); 
      } 
    } 
    
    if (originalFood.name != newName) { 
      bool? currentVisibility = draggableLabelVisibility.remove("custom_${originalFood.name}"); 
      draggableLabelVisibility["custom_${newName}"] = currentVisibility ?? true; 
    } 
    
    originalFood.name = newName; 
    originalFood.protein = protein; 
    originalFood.fa = fa; 
    originalFood.enerji = enerji; 
    
    await _saveCustomFoods(); 
    _resetPdfSnapshot(); 
    notifyListeners(); 
  }
  
  Future<void> deleteCustomFood(int index) async { 
    if (index < 0 || index >= customFoods.length) return; 
    final deletedFood = customFoods[index]; 
    
    if (deletedFood.isDefault) { 
      throw Exception("Varsayılan besinler ('${deletedFood.name}') silinemez."); 
    } 
    
    customFoods.removeAt(index); 
    draggableLabelVisibility.remove("custom_${deletedFood.name}"); 
    
    _resetPdfSnapshot(); 
    await _saveCustomFoods(); 
    notifyListeners(); 
  }
  
  int getProteinTableHighlightedIndex(int ageInMonths, int ageInYears) {
    
    final finalAgeInMonths = calculatedHeightAgeInMonths != -1 ? calculatedHeightAgeInMonths : ageInMonths;
    final finalAgeInYears = finalAgeInMonths >= 12 ? (finalAgeInMonths / 12.0).floor() : 0;
    
    if (finalAgeInMonths <= 3) return 0; 
    if (finalAgeInMonths <= 6) return 1; 
    if (finalAgeInMonths <= 12) return 2; 

    final ageInYearsFloor = finalAgeInYears;
    if (ageInYearsFloor >= 1 && ageInYearsFloor <= 3) return 3; 
    if (ageInYearsFloor >= 4 && ageInYearsFloor <= 6) return 4; 
    if (ageInYearsFloor >= 7 && ageInYearsFloor <= 9) return 5; 
    if (ageInYearsFloor >= 10) return 6; 

    return -1;
  }

  // EKLENDİ: Chart Data metotları
  List<FlSpot> _getPercentileSpots<T>({
    required List<T> data,
    required String gender,
    required List<double> Function(T) getPercentiles,
    required double targetPercentile,
    required List<double> percentileValues,
  }) {
    final int percentileIndex = percentileValues.indexOf(targetPercentile);
    if (percentileIndex == -1) return [];

    final List<FlSpot> spots = [];
    
    final filteredData = data.where((d) {
        if (d is PercentileData) return d.gender == selectedGender;
        if (d is LengthPercentileData) return d.gender == selectedGender;
        if (d is BMIPercentileData) return d.gender == selectedGender; 
        return false;
    }).toList();
    
    for (final d in filteredData) {
      final int ageInMonths = d is PercentileData 
          ? d.ageInMonths 
          : (d is LengthPercentileData ? d.ageInMonths : (d is BMIPercentileData ? d.ageInMonths : -1));

      if (ageInMonths != -1) {
        final List<double> pValues = getPercentiles(d);
        if (percentileIndex < pValues.length) {
          final value = pValues[percentileIndex];
          spots.add(FlSpot(ageInMonths.toDouble() / 12.0, value)); 
        }
      }
    }
    return spots;
  }
  
  LineChartData getWeightChartDataNeyzi(double weight, int ageInMonths) {
    const percentileLabels = [3.0, 10.0, 25.0, 50.0, 75.0, 90.0, 97.0];
    return _buildChartData(
      sourceData: _persentilService.neyziWeightPercentileData,
      percentileLabels: percentileLabels,
      getPercentiles: (d) => d.neyziPercentiles,
      userWeight: weight,
      ageInMonths: ageInMonths,
      maxY: 80,
    );
  }
  
  LineChartData getWeightChartDataWHO(double weight, int ageInMonths) {
    const percentileLabels = [3.0, 5.0, 10.0, 25.0, 50.0, 75.0, 90.0, 95.0, 97.0];
    return _buildChartData(
      sourceData: _persentilService.whoPercentileData,
      percentileLabels: percentileLabels,
      getPercentiles: (d) { 
        return [
          d.percentile3,
          d.percentile5,
          d.percentile10,
          d.percentile25,
          d.percentile50,
          d.percentile75,
          d.percentile90,
          d.percentile95,
          d.percentile97,
        ];
      },
      userWeight: weight,
      ageInMonths: ageInMonths,
      maxY: 80,
    );
  }

  LineChartData _buildChartData<T>({
    required List<T> sourceData,
    required List<double> percentileLabels,
    required List<double> Function(T) getPercentiles,
    required double userWeight,
    required int ageInMonths,
    required double maxY,
  }) {
    final List<LineChartBarData> lineBarsData = [];

    for (final pValue in percentileLabels) {
      final List<FlSpot> spots = _getPercentileSpots<T>(
        data: sourceData,
        gender: selectedGender,
        getPercentiles: getPercentiles,
        targetPercentile: pValue,
        percentileValues: percentileLabels,
      );

      Color lineColor;
      if (pValue <= 10.0 || pValue >= 90.0) {
        lineColor = Colors.red.shade400; 
      } else if (pValue == 50.0) {
        lineColor = Colors.green.shade400; 
      } else {
        lineColor = Colors.orange.shade400; 
      }

      lineBarsData.add(
        LineChartBarData(
          spots: spots,
          isCurved: true,
          color: lineColor,
          barWidth: 1.5,
          dotData: const FlDotData(show: false), 
          belowBarData: BarAreaData(show: false),
        ),
      );
    }
    
    if (userWeight > 0 && ageInMonths >= 0) {
      final userSpot = FlSpot(ageInMonths.toDouble() / 12.0, userWeight); 
      lineBarsData.add(
        LineChartBarData(
          spots: [userSpot],
          isCurved: false,
          color: Colors.blue.shade900,
          barWidth: 0,
          dotData: FlDotData(
            show: true,
            getDotPainter: (spot, percent, bar, index) => FlDotCirclePainter(
              radius: 4,
              color: Colors.blue.shade900,
              strokeWidth: 1,
              strokeColor: Colors.white,
            ),
          ),
        ),
      );
    }

    final chronoAgeInYearsForXAxis = ageInMonths / 12.0;
    final maxX = chronoAgeInYearsForXAxis > 15 ? chronoAgeInYearsForXAxis + 1 : 15.0; 

    return LineChartData(
      lineBarsData: lineBarsData,
      gridData: const FlGridData(show: true, drawVerticalLine: true),
      titlesData: FlTitlesData(
        show: true,
        bottomTitles: AxisTitles( 
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 30,
            interval: 1, 
            getTitlesWidget: (value, meta) {
              if (value == 0) return const Text('Doğum', style: TextStyle(fontSize: 10));
              if (value % 1 == 0) { 
                 return Text('${value.toInt()} Yıl', style: const TextStyle(fontSize: 10));
              }
              return const Text(''); 
            },
          ),
        ),
        leftTitles: AxisTitles( 
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 40,
            interval: 5,
            getTitlesWidget: (value, meta) => Text(value.toStringAsFixed(0), style: const TextStyle(fontSize: 10)),
          ),
        ),
        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      ),
      borderData: FlBorderData(show: true, border: Border.all(color: Colors.grey.shade300, width: 1)),
      minX: 0,
      maxX: maxX,
      minY: 0,
      maxY: maxY,
      lineTouchData: LineTouchData( 
          enabled: true,
          touchTooltipData: LineTouchTooltipData(
              getTooltipItems: (List<LineBarSpot> touchedSpots) {
                  return touchedSpots.map((LineBarSpot touchedSpot) {
                      const style = TextStyle(color: Colors.white, fontWeight: FontWeight.bold);
                      if (touchedSpot.barIndex == touchedSpots.length - 1) {
                          final percentileText = calculatedPercentiles.weightPercentile != '-'
                              ? calculatedPercentiles.weightPercentile
                              : "Veri Eksik";
                              
                          return LineTooltipItem(
                              'Mevcut: ${_amountFormat.format(touchedSpot.y)} kg\nAr.: $percentileText',
                              style,
                          );
                      }
                      return null;
                  }).toList();
              },
          ),
      ),
    );
  }
  // PDF oluşturma mantığı: pdf.addPage...
  Future<Uint8List?> _generatePdfBytes() async {
    _takePdfBesinTablosuSnapshot();
    if (_pdfBesinTablosuSnapshot == null || _pdfBesinTablosuSnapshot!.isEmpty) {
      _resetPdfSnapshot();
      return null;
    }
    
    final pdf = pw.Document();
    final font = await rootBundle.load("assets/fonts/NotoSans-Regular.ttf"); 
    final ttf = pw.Font.ttf(font);

    final h1 = pw.TextStyle(font: ttf, fontSize: 18, fontWeight: pw.FontWeight.bold);
    final h2 = pw.TextStyle(font: ttf, fontSize: 14, fontWeight: pw.FontWeight.bold, color: PdfColor.fromHex("333333"));
    final p = pw.TextStyle(font: ttf, fontSize: 10);
    final boldP = pw.TextStyle(font: ttf, fontSize: 10, fontWeight: pw.FontWeight.bold);

    final patientNameForPdf = nameController.text.isNotEmpty ? nameController.text : "Belirtilmedi";
    
    final weight = weightController.text.isNotEmpty ? weightController.text : "-"; 
    final height = heightController.text.isNotEmpty ? heightController.text : "-";
    
    final dobText = dateOfBirth != null ? DateFormat('dd.MM.yyyy').format(dateOfBirth!) : "-";
    final ageText = calculatedAgeDisplayString;
    
    final gender = selectedGender;
    final special = [
      isPremature ? "Prematüre" : null,
      isPregnant ? "Gebe" : null
    ].where((e) => e != null).join(", ");
    
    final faf = fafController.text.isNotEmpty ? fafController.text : "-";

    pw.Widget _buildPdfInfoRow(String label, String value, pw.TextStyle style) {
      if (value == '-' || value.isEmpty) return pw.SizedBox.shrink();
      return pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 2),
        child: pw.Row(
          children: [
            pw.Container(width: 120, child: pw.Text('$label:', style: style)),
            pw.Text(value, style: style.copyWith(fontWeight: pw.FontWeight.normal)),
          ],
        ),
      );
    }

    pw.Widget _buildPdfReqRow(String label, String value, String unit, pw.TextStyle style) {
      final displayValue = value.contains('/') || value.contains('-') || value.contains('kg') || value.isEmpty ? value : '$value $unit';
      
      if (value.isEmpty) return pw.SizedBox.shrink();
      return pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 2),
        child: pw.Row(
          children: [
            pw.Container(width: 120, child: pw.Text('$label:', style: style)),
            pw.Text(displayValue, style: style.copyWith(fontWeight: pw.FontWeight.normal)),
          ],
        ),
      );
    }

    pw.Widget _buildPdfMealSection(String title, List<MealEntry> entries, pw.TextStyle p, pw.TextStyle boldP) {
      if (entries.isEmpty) return pw.SizedBox.shrink();
      return pw.Container(
        width: 250,
        decoration: pw.BoxDecoration( 
          border: pw.Border.all(color: PdfColor.fromHex('888888')), 
          borderRadius: pw.BorderRadius.circular(4)
        ),
        padding: const pw.EdgeInsets.all(6),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(title, style: boldP.copyWith(color: PdfColors.blue800)),
            pw.SizedBox(height: 4),
            pw.Wrap(
              spacing: 4,
              runSpacing: 4,
              children: entries.map((entry) => pw.Container(
                decoration: pw.BoxDecoration( 
                  color: PdfColor.fromHex('E0F2F1'), 
                  borderRadius: pw.BorderRadius.circular(10),
                  border: pw.Border.all(color: PdfColor.fromHex('4DB6AC'), width: 0.5), 
                ),
                padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                child: pw.Text(entry.toString(), style: p.copyWith(fontSize: 8)),
              )).toList(),
            ),
          ],
        ),
      );
    }


    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('Metabolizma Hesaplayıcı Raporu', style: h1),
              pw.SizedBox(height: 20),

              pw.Text('1. Kişisel Bilgiler ve Gereksinimler', style: h2),
              pw.Divider(color: PdfColor.fromHex("666666")),
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Container(
                    width: 250,
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('Temel Veriler:', style: boldP),
                        _buildPdfInfoRow("Adı Soyadı (Hasta)", patientNameForPdf, p), 
                        _buildPdfInfoRow("Doğum Tarihi", dobText, p),
                        _buildPdfInfoRow("Yaş (Kronolojik)", ageText, p),
                        _buildPdfInfoRow("Cinsiyet", gender, p),
                        pw.Text("Ağırlık (Mevcut/Grafik): $weight kg", style: p),
                        pw.Text("Boy: $height cm", style: p),
                        pw.Text("Hesaplama Yaşı: ${calculatedHeightAgeInMonths != -1 
                            ? "Boy Yaşı (${(calculatedHeightAgeInMonths/12).toStringAsFixed(1)} Yıl)" 
                            : "Kronolojik Yaş"}", style: p),
                        if (special.isNotEmpty) _buildPdfInfoRow("Özel Durum", special, p),
                        pw.SizedBox(height: 10),
                        pw.Text('Persentil Sonuçları:', style: boldP),
                        _buildPdfInfoRow("Ağırlık Persentili", calculatedPercentiles.weightPercentile, p), 
                        _buildPdfInfoRow("Boy Persentili", calculatedPercentiles.heightPercentile, p),
                        _buildPdfInfoRow("BKİ Persentili", calculatedPercentiles.bmiPercentile, p),
                        pw.SizedBox(height: 10),
                        pw.Text("BMH (kcal/gün): ${bmhController.text}", style: boldP),
                        pw.Text("BKİ: ${bmiController.text}", style: boldP),
                        _buildPdfInfoRow("FAF (Giriş)", faf, boldP),
                      ],
                    ),
                  ),
                  pw.Container(
                    width: 250,
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text("Günlük Gereksinimler (Referans)", style: p.copyWith(fontWeight: pw.FontWeight.bold)),
                        pw.SizedBox(height: 5),
                        _buildPdfReqRow("Enerji (PKU Ref)", energyReqController.text, "", boldP), 
                        _buildPdfReqRow("Enerji (Pratik)", energyReq2Controller.text, "kcal", boldP),
                        _buildPdfReqRow("Enerji (BMH*FAF+BGE)", energyReq3Controller.text, "kcal", boldP),
                        _buildPdfReqRow("Protein (Eski Ref)", proteinReqController.text, "g", boldP), 
                        _buildPdfReqRow("Fenilalanin (PKU Ref)", pheReqController.text, "", boldP), 
                      ],
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 20),

              pw.Text('2. Besin Girişi ve Toplamlar (Başlangıç Miktarları)', style: h2),
              pw.Divider(color: PdfColor.fromHex("666666")),
              
              pw.Table.fromTextArray(
                headers: ['Besin Adı', 'Miktar', 'Enerji (kcal)', 'Protein (g)', 'FA (mg)'],
                data: _pdfBesinTablosuSnapshot!,
                border: pw.TableBorder.all(color: PdfColors.grey500),
                headerStyle: boldP.copyWith(color: PdfColors.white),
                headerDecoration: const pw.BoxDecoration(color: PdfColors.teal700),
                cellStyle: p,
                columnWidths: {
                  0: const pw.FlexColumnWidth(3),
                  1: const pw.FlexColumnWidth(2),
                  2: const pw.FlexColumnWidth(2),
                  3: const pw.FlexColumnWidth(2),
                  4: const pw.FlexColumnWidth(2),
                },
              ),
              pw.SizedBox(height: 5),

              pw.Table(
                border: pw.TableBorder.all(color: PdfColors.grey500),
                columnWidths: {
                  0: const pw.FlexColumnWidth(3), 
                  1: const pw.FlexColumnWidth(2), 
                  2: const pw.FlexColumnWidth(2), 
                  3: const pw.FlexColumnWidth(2), 
                  4: const pw.FlexColumnWidth(2), 
                },
                children: [
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                    children: [
                      pw.Padding(
                        padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 4),
                        child: pw.Text("TOPLAM:", style: boldP.copyWith(fontSize: 11)),
                      ),
                      pw.SizedBox(), 
                      pw.Padding(
                        padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 4),
                        child: pw.Align(
                          alignment: pw.Alignment.centerRight,
                          child: pw.Text(_pdfTotalsSnapshotEnerji!, style: boldP.copyWith(fontSize: 11)),
                        ),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 4),
                        child: pw.Align(
                          alignment: pw.Alignment.centerRight,
                          child: pw.Text(_pdfTotalsSnapshotProtein!, style: boldP.copyWith(fontSize: 11)),
                        ),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 4),
                        child: pw.Align(
                          alignment: pw.Alignment.centerRight,
                          child: pw.Text(_pdfTotalsSnapshotFenilalanin!, style: boldP.copyWith(fontSize: 11)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              pw.SizedBox(height: 20),

              pw.Text('3. Öğün Planı', style: h2),
              pw.Divider(color: PdfColor.fromHex("666666")),
              
              pw.Wrap(
                spacing: 10,
                runSpacing: 10,
                children: mealPlanOrder.map((item) {
                  if (item.isCustom) {
                    final customMeal = item.reference as CustomMealSection;
                    return _buildPdfMealSection(customMeal.name, customMeal.entries, p, boldP);
                  } else {
                    final mealType = item.reference as MealType;
                    return _buildPdfMealSection(getMealTitle(mealType), mealEntries[mealType]!, p, boldP);
                  }
                }).toList(),
              ),
              
              pw.Spacer(),
              pw.Text('Rapor Tarihi: ${DateFormat('dd.MM.yyyy HH:mm').format(DateTime.now())}', style: p.copyWith(fontSize: 8, color: PdfColors.grey500)),
            ],
          );
        },
      ),
    );

    try {
      final bytes = await pdf.save();
      _resetPdfSnapshot();
      return bytes;
    } catch (e) {
      _resetPdfSnapshot();
      print("PDF Byte oluşturma hatası: ${e.toString()}");
      return null;
    }
  }

  // YENİ METOT: JSON kayıt verisini (PatientRecord) hazırlar ve döndürür.
({String jsonString, PatientRecord record}) _prepareJsonRecordData(String userId) {
    // Yaş hesaplaması: (years, monthsTotal, days, doubleAge) döner
    final (years, totalMonths, days, _) = _calculateAge(dateOfBirth, visitDate);
    final currentWeight = double.tryParse(weightController.text.replaceAll(',', '.')) ?? 0.0;
    final currentHeight = double.tryParse(heightController.text.replaceAll(',', '.')) ?? 0.0;

    print('DEBUG _prepareJsonRecordData ÇAĞRILDI:');
    print('DEBUG totalMonths = $totalMonths, currentWeight = $currentWeight, currentHeight = $currentHeight, selectedGender = $selectedGender');
    
    // ÖNEMLİ: Kayıt sırasında persentilleri YENIDEN HESAPLA (calculatedPercentiles'a güvenme!)
    final freshPercentiles = persentilCalculator.calculateAllPercentiles(
      chronologicalAgeInMonths: totalMonths,
      gender: selectedGender,
      weight: currentWeight,
      height: currentHeight,
    );
    
    print('DEBUG freshPercentiles.neyziWeightPercentile = ${freshPercentiles.neyziWeightPercentileChronoAge}');
    print('DEBUG freshPercentiles.whoWeightPercentile = ${freshPercentiles.whoWeightPercentileChronoAge}');
    print('DEBUG freshPercentiles.neyziHeightPercentile = ${freshPercentiles.neyziHeightPercentile}');

    final recordJson = serializeDataToJson();
    final newRecord = PatientRecord(
      ownerUserId: userId,
      patientName: nameController.text.trim(),
      recordDate: DateTime.now(), // HER ZAMAN GÜNCEL TARİH (Güncelleme/Kayıt takibi için)
      pdfFilePath: null, 
      jsonFilePath: null, 
      recordDataJson: recordJson,
      // YENİ EKLENEN VERİLER
      weight: currentWeight,
      selectedGender: selectedGender,
      chronologicalAgeInMonths: totalMonths, // Toplam Ay
      chronologicalAgeYears: years, // Yıl
      chronologicalAgeMonths: totalMonths % 12, // Kalan Ay
      height: currentHeight,
      // Büyüme Gelişme Verileri - TAZE HESAPLANAN DEĞERLERİ KUL LAN!
      neyziWeightPercentile: freshPercentiles.neyziWeightPercentileChronoAge,
      whoWeightPercentile: freshPercentiles.whoWeightPercentileChronoAge,
      neyziHeightPercentile: freshPercentiles.neyziHeightPercentile,
      whoHeightPercentile: freshPercentiles.whoHeightPercentile,
      neyziBmiPercentile: freshPercentiles.neyzieBmiPercentileChronoAge,
      whoBmiPercentile: freshPercentiles.whoBmiPercentileChronoAge,
      neyziHeightAgeStatus: freshPercentiles.neyziHeightAgeStatus,
      whoHeightAgeStatus: freshPercentiles.whoHeightAgeStatus,
      neyziHeightAgeInMonths: freshPercentiles.neyziHeightAgeInMonths,
      whoHeightAgeInMonths: freshPercentiles.whoHeightAgeInMonths,
    );
    final jsonString = jsonEncode(newRecord.toJson());
    return (jsonString: jsonString, record: newRecord);
}
  // GÜNCELLENDİ: Harici kaydetme için byte verilerini ve Record nesnesini döndürür.
  Future<({Uint8List? pdfBytes, Uint8List jsonBytes, PatientRecord record})> prepareSaveData(String userId) async {
    final data = _prepareJsonRecordData(userId);
    final jsonBytes = Uint8List.fromList(utf8.encode(data.jsonString));
    final pdfBytes = await _generatePdfBytes();

    return (pdfBytes: pdfBytes, jsonBytes: jsonBytes, record: data.record);
  }

  // Eski exportToPdf metodu (Manuel PDF Oluştur butonu için) - Sadece PDF'i kaydeder/indirir.
  Future<String?> exportToPdf() async {
    final pdfBytes = await _generatePdfBytes();
    if (pdfBytes == null) return "Uyarı: PDF oluşturmak için veri bulunamadı.";
    
    final patientName = nameController.text.isNotEmpty ? nameController.text : "Rapor";
    final dateStr = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final fileName = "${patientName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')}_Manuel_Rapor_$dateStr";
    
    try {
        final path = await FileSaver.instance.saveFile(
          name: fileName,
          bytes: pdfBytes,
          ext: 'pdf',
          mimeType: MimeType.pdf,
        );
        return "PDF dosyası başarıyla kaydedildi/indirildi: $path";
    } catch (e) {
        return "Hata: Manuel PDF kaydetme/indirme başarısız oldu. (${e.toString()})";
    }
  }


  String serializeDataToJson() {
      final data = {
      'name': nameController.text,
      'height': heightController.text,
      'weight': weightController.text,
      'calculationWeight': calculationWeightController.text,
      'dateOfBirth': dateOfBirth?.toIso8601String(),
      'gender': selectedGender,
      'pheLevel': pheLevelController.text, // YENİ
      'visitDate': visitDate?.toIso8601String(), // YENİ
      'isPregnant': isPregnant,
      'isPremature': isPremature,
      'faf': fafController.text,
      'selectedWeightSource': selectedWeightSource?.name,
      'selectedPercentileValue': selectedPercentileValue,
      'currentRecordId': currentRecordId,
      'foodRows': foodRows.map((row) => {
        'name': row.nameController.text,
        'amount': row.amountController.text,
        'originalValues': row.originalValues != null ? {
          'fa': row.originalValues!.fenilalaninDegeri, 
          'protein': row.originalValues!.proteinDegeri, 
          'enerji': row.originalValues!.enerjiDegeri, 
        } : null,
        'originalLabelName': row.originalLabelName,
        'initialAmount': row.initialAmount,
      }).toList(),
      'mealEntries': mealEntries.map((key, value) => MapEntry(
        key.name,
        value.map((entry) => {
          'sourceRowIndex': entry.sourceRowIndex,
          'foodName': entry.foodName,
          'assignedAmount': entry.assignedAmount,
        }).toList(),
      )),
      'customMealSections': customMealSections.map((meal) => {
        'name': meal.name,
        'entries': meal.entries.map((entry) => {
          'sourceRowIndex': entry.sourceRowIndex,
          'foodName': entry.foodName,
          'assignedAmount': entry.assignedAmount,
        }).toList(),
      }).toList(),
      'mealPlanOrder': mealPlanOrder.map((item) => {
        'name': item.name,
        'isCustom': item.isCustom,
        'referenceName': item.isCustom ? (item.reference as CustomMealSection).name : (item.reference as MealType).name,
      }).toList(),
      'selectedEnergySources': selectedEnergySources.map((key, value) => MapEntry(key.name, value)),
    };
    return jsonEncode(data);
  }
  
  void deserializeDataFromJson(String jsonString) {
    clearAllData(notify: false); 
    
    if (jsonString.isEmpty) return;
    
    final Map<String, dynamic> data = jsonDecode(jsonString);

    nameController.text = data['name'] ?? '';
    heightController.text = data['height'] ?? '';
    weightController.text = data['weight'] ?? '';
    calculationWeightController.text = data['calculationWeight'] ?? '';

    final vdStr = data['visitDate'] as String?; 
    if (vdStr != null) {
      visitDate = DateTime.tryParse(vdStr);
      visitDateController.text = visitDate != null ? DateFormat('dd.MM.yyyy').format(visitDate!) : '';
    } else {
      visitDate = null;
      visitDateController.text = '';
    }
    
    final dobStr = data['dateOfBirth'] as String?;
    if (dobStr != null) {
      dateOfBirth = DateTime.tryParse(dobStr);
      dateOfBirthController.text = dateOfBirth != null ? DateFormat('dd.MM.yyyy').format(dateOfBirth!) : '';
    }
    
    selectedGender = data['gender'] ?? 'Erkek';
    isPregnant = data['isPregnant'] ?? false;
    isPremature = data['isPremature'] ?? false;
    fafController.text = data['faf'] ?? "1.2";
    
    final ws = data['selectedWeightSource'] as String?;
    selectedWeightSource = ws != null ? WeightSource.values.firstWhereOrNull((e) => e.name == ws) : null;
    selectedPercentileValue = (data['selectedPercentileValue'] as num?)?.toDouble();
    currentRecordId = data['currentRecordId'] as String?;

    final List<dynamic> jsonFoodRows = data['foodRows'] ?? [];
    foodRows.clear();
    for (int i = 0; i < jsonFoodRows.length; i++) {
        final rowData = jsonFoodRows[i];
        final newRow = FoodRowState();
        
        newRow.nameController.text = rowData['name'] ?? '';
        newRow.amountController.text = rowData['amount'] ?? '0';
        
        final originalValuesJson = rowData['originalValues'];
        if (originalValuesJson != null) {
          newRow.originalValues = BesinVerisi(
            fenilalaninDegeri: (originalValuesJson['fa'] as num).toDouble(),
            proteinDegeri: (originalValuesJson['protein'] as num).toDouble(),
            enerjiDegeri: (originalValuesJson['enerji'] as num).toDouble(),
          );
          newRow.originalLabelName = rowData['originalLabelName'];
          newRow.initialAmount = (rowData['initialAmount'] as num?)?.toDouble() ?? 0.0;
          if (newRow.originalLabelName != null) {
             draggableLabelVisibility[newRow.originalLabelName!] = false;
          }
        } else {
             newRow.initialAmount = 0.0;
        }
        
        foodRows.add(newRow);
        _addListenersForRow(i); 
    }
    while (foodRows.length < 5) {
      foodRows.add(FoodRowState());
      _addListenersForRow(foodRows.length - 1);
    }
    
    mealEntries.clear();
    final jsonMealEntries = data['mealEntries'] as Map<String, dynamic>? ?? {};
    for (var mealType in MealType.values) {
        final entriesList = jsonMealEntries[mealType.name] as List<dynamic>? ?? [];
        mealEntries[mealType] = entriesList.map((entryData) => MealEntry(
            sourceRowIndex: entryData['sourceRowIndex'] ?? 0,
            foodName: entryData['foodName'] ?? '',
            assignedAmount: (entryData['assignedAmount'] as num?)?.toDouble() ?? 0.0,
        )).toList();
    }
    
    customMealSections.clear();
    final jsonCustomMealSections = data['customMealSections'] as List<dynamic>? ?? [];
    final Map<String, CustomMealSection> customMealMap = {};

    for (var customMealData in jsonCustomMealSections) {
        final customMeal = CustomMealSection(customMealData['name'] ?? 'Özel Öğün');
        final entriesList = customMealData['entries'] as List<dynamic>? ?? [];
        customMeal.entries = entriesList.map((entryData) => MealEntry(
            sourceRowIndex: entryData['sourceRowIndex'] ?? 0,
            foodName: entryData['foodName'] ?? '',
            assignedAmount: (entryData['assignedAmount'] as num?)?.toDouble() ?? 0.0,
        )).toList();
        customMealSections.add(customMeal);
        customMealMap[customMeal.name] = customMeal;
    }
    
    mealPlanOrder.clear();
    final jsonMealPlanOrder = data['mealPlanOrder'] as List<dynamic>? ?? [];
    for (var itemData in jsonMealPlanOrder) {
        final name = itemData['name'] ?? '';
        final isCustom = itemData['isCustom'] ?? false;
        final refName = itemData['referenceName'] ?? '';
        
        if (isCustom && customMealMap.containsKey(name)) {
             mealPlanOrder.add(MealPlanItem(name: name, reference: customMealMap[name]!, isCustom: true));
        } else {
             final mealType = MealType.values.firstWhereOrNull((e) => e.name == refName);
             if (mealType != null) {
                mealPlanOrder.add(MealPlanItem(name: name, reference: mealType, isCustom: false));
             }
        }
    }
    if (mealPlanOrder.isEmpty) {
      _initializeMealPlanOrder();
    }
    
    final jsonSelectedEnergySources = data['selectedEnergySources'] as Map<String, dynamic>? ?? {};
    selectedEnergySources = {
      EnergySource.doctor: jsonSelectedEnergySources['doctor'] ?? false,
      EnergySource.fku: jsonSelectedEnergySources['fku'] ?? true,
      EnergySource.practical: jsonSelectedEnergySources['practical'] ?? false,
      EnergySource.bmhFafBge: jsonSelectedEnergySources['bmhFafBge'] ?? false,
    };


    _initializeCalculations(); 
    notifyListeners();
  }

  void loadPatientData(PatientRecord record) {
    loadedPatientName = record.patientName;
    currentRecordId = record.recordId;
    currentRecord = record;
    isNeyziWeightCardFront = true;
    isWhoWeightCardFront = true;
    deserializeDataFromJson(record.recordDataJson);
    
    // PatientRecord'dan gelen değerleri kullan (JSON'daki'nin üzerine yaz)
    // ÖNEMLI: deserialize'dan sonra yapılır ki JSON değerleri override edilsin
    selectedGender = record.selectedGender;
    heightController.text = record.height.toStringAsFixed(1);
    weightController.text = record.weight.toStringAsFixed(1);
    
    // Kişisel bilgiler yüklendikten sonra persentil ve büyüme-gelişme hesaplamalarını tetikle
    _performAndUpdatePersonalCalculations();
    notifyListeners();
  }
  
  void clearAllData({bool notify = true}) {
      nameController.clear();
      heightController.clear();
      weightController.clear();
      calculationWeightController.clear();
      
      dateOfBirth = null;
      dateOfBirthController.clear();
      
      selectedGender = 'Erkek';
      isPregnant = false;
      isPremature = false;
      fafController.text = "1.2";
      selectedWeightSource = null;
      selectedPercentileValue = null;
      currentRecordId = null;
      loadedPatientName = "";
      isNeyziWeightCardFront = true;
      isWhoWeightCardFront = true;
      // YENİ EKLENECEK SATIRLAR
      pheLevelController.clear();
      visitDateController.clear();
      doctorProteinController.clear();
      doctorPheController.clear();

      // Snapshot değerlerini ve bayrağı temizle
      _snapshotTotalEnergy = 0.0;
      _snapshotTotalProtein = 0.0;
      _snapshotTotalPhe = 0.0;
      _isMealAssignmentActive = false;

      for (var row in foodRows) {
          if (row.originalLabelName != null) {
              draggableLabelVisibility[row.originalLabelName!] = true; 
          }
          row.dispose(); 
      }
      foodRows.clear();
      foodRows = List.generate(5, (_) => FoodRowState());
      for (int i = 0; i < 5; i++) {
         _addListenersForRow(i);
      }

      mealEntries.forEach((key, value) => value.clear());
      customMealSections.clear();
      _initializeMealPlanOrder();
      
      _performAndUpdatePersonalCalculations(notify: false);
      _recalculateAllRowsAndTotals(notify: false);

      if (notify) notifyListeners();
  }
  
  void setCurrentRecordId(String id) {
      currentRecordId = id;
  }

  String getMealTitle(MealType mealType) { 
    switch (mealType) { 
      case MealType.sabah: return "Sabah"; 
      case MealType.kusluk: return "Kuşluk"; 
      case MealType.ogle: return "Öğle"; 
      case MealType.ikindi: return "İkindi"; 
      case MealType.aksam: return "Akşam"; 
      case MealType.gece: return "Gece"; 
    } 
  }
}