// lib/screens/growth_assessment_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/models.dart';
import '../viewmodels/metabolizma_viewmodel.dart';

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
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final viewModel = Provider.of<MetabolizmaViewModel>(context, listen: false);
      viewModel.loadPatientData(widget.initialRecord);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Büyüme ve Gelişme Değerlendirmesi'),
        centerTitle: true,
      ),
      body: Consumer<MetabolizmaViewModel>(
        builder: (context, viewModel, _) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildPatientInfoCard(),
                const SizedBox(height: 20),
                _buildGrowthAssessmentSection(),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildPatientInfoCard() {
    final record = widget.initialRecord;
    final isMale = record.selectedGender.toLowerCase() == 'erkek';
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
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildInfoBox('Yaş', '${record.chronologicalAgeYears} yıl ${record.chronologicalAgeMonths} ay\n(${record.chronologicalAgeInMonths} ay)', Icons.cake),
                _buildInfoBox('Cinsiyet', record.selectedGender == 'Erkek' ? 'Erkek' : 'Kız', Icons.person),
                _buildInfoBox('Boy', record.height > 0 ? '${record.height.toStringAsFixed(1)} cm' : '-', Icons.height),
                _buildInfoBox('Ağırlık', record.weight > 0 ? '${record.weight.toStringAsFixed(1)} kg' : '-', Icons.monitor_weight),
                _buildInfoBox('BKİ', bmi > 0 ? bmi.toStringAsFixed(1) : '-', Icons.analytics),
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
          Icon(icon, size: 20, color: Colors.grey.shade700),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildGrowthAssessmentSection() {
    final record = widget.initialRecord;
    final hasData = record.weight > 0 && record.height > 0;

    if (!hasData) {
      return const Center(child: Text('Persentil verisi bulunamadı'));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Ağırlık Persentili
        Row(
          children: [
            Expanded(
              child: _buildPercentileBox(
                'Ağırlık Persentili\nNEYZİ',
                record.neyziWeightPercentile,
                Colors.orange,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildPercentileBox(
                'Ağırlık Persentili\nWHO',
                record.whoWeightPercentile,
                Colors.blue,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Boy Persentili
        Row(
          children: [
            Expanded(
              child: _buildPercentileBox(
                'Boy Persentili\nNEYZİ',
                record.neyziHeightPercentile,
                Colors.orange,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildPercentileBox(
                'Boy Persentili\nWHO',
                record.whoHeightPercentile,
                Colors.blue,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // BKİ Persentili
        Row(
          children: [
            Expanded(
              child: _buildPercentileBox(
                'BKİ Persentili\nNEYZİ',
                record.neyziBmiPercentile,
                Colors.orange,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildPercentileBox(
                'BKİ Persentili\nWHO',
                record.whoBmiPercentile,
                Colors.blue,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Boy Yaşı Durumu
        Row(
          children: [
            Expanded(
              child: _buildPercentileBox(
                'Boy Yaşı Durumu\nNEYZİ',
                record.neyziHeightAgeStatus,
                Colors.orange,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildPercentileBox(
                'Boy Yaşı Durumu\nWHO',
                record.whoHeightAgeStatus,
                Colors.blue,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPercentileBox(String label, String value, Color color) {
    return Container(
      decoration: BoxDecoration(
        color: color.withOpacity(0.05),
        border: Border.all(color: color, width: 2),
        borderRadius: BorderRadius.circular(4),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: color,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: Colors.black,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
