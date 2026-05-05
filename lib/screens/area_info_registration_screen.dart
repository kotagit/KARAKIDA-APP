import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/sheets_provider.dart';
import '../services/firestore_service.dart';

class AreaInfoRegistrationScreen extends StatefulWidget {
  const AreaInfoRegistrationScreen({super.key});

  @override
  State<AreaInfoRegistrationScreen> createState() =>
      _AreaInfoRegistrationScreenState();
}

class _AreaInfoRegistrationScreenState
    extends State<AreaInfoRegistrationScreen> {
  

  final _formKey = GlobalKey<FormState>();
  final _addressController = TextEditingController();
  final _buildingNameController = TextEditingController();
  final _rejectReasonController = TextEditingController();
  final _memoController = TextEditingController();

  bool _submitting = false;

  @override
  void dispose() {
    _addressController.dispose();
    _buildingNameController.dispose();
    _rejectReasonController.dispose();
    _memoController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final confirmed = await _showConfirmDialog();
    if (confirmed != true) return;

    setState(() => _submitting = true);

    final userName =
        context.read<SheetsProvider>().currentUserName ?? '不明';

    final success = await FirestoreService.submitAreaInfo(
      name: userName,
      address: _addressController.text.trim(),
      buildingName: _buildingNameController.text.trim(),
      rejectReason: _rejectReasonController.text.trim(),
      memo: _memoController.text.trim(),
    );

    // 管理者にも通知
    if (success) {
      await FirestoreService.notifyAdmin(
        type: 'area_info',
        message: '$userNameさんが新規物件情報を登録しました',
        fromUser: userName,
        extra: {
          'address': _addressController.text.trim(),
          'buildingName': _buildingNameController.text.trim(),
        },
      );
    }

    if (mounted) {
      setState(() => _submitting = false);

      if (success) {
        _addressController.clear();
        _buildingNameController.clear();
        _rejectReasonController.clear();
        _memoController.clear();

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('登録しました'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('登録に失敗しました'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<bool?> _showConfirmDialog() {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('送信内容の確認'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _confirmRow('住所', _addressController.text.trim()),
              _confirmRow('建物名', _buildingNameController.text.trim()),
              _confirmRow('拒否理由', _rejectReasonController.text.trim()),
              _confirmRow('メモ', _memoController.text.trim()),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('修正する'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.primary,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('送信する'),
          ),
        ],
      ),
    );
  }

  Widget _confirmRow(String label, String value) {
    if (value.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(height: 2),
          Text(value, style: const TextStyle(fontSize: 14)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('区域情報登録'),
        titleTextStyle: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
      body: _submitting
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      '新しい物件情報を登録してください',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.black54,
                      ),
                    ),
                    const SizedBox(height: 24),
                    _buildTextField(
                      controller: _addressController,
                      label: '住所',
                      hint: '例: 多摩市鶴牧3-5',
                      icon: Icons.location_on_outlined,
                      required: true,
                    ),
                    const SizedBox(height: 16),
                    _buildTextField(
                      controller: _buildingNameController,
                      label: '建物名',
                      hint: '例: グリーンハイツ唐木田 101号室',
                      icon: Icons.apartment_outlined,
                      required: false,
                    ),
                    const SizedBox(height: 16),
                    _buildTextField(
                      controller: _rejectReasonController,
                      label: '拒否理由',
                      hint: '例: 表札に訪問お断り',
                      icon: Icons.block_outlined,
                      required: false,
                    ),
                    const SizedBox(height: 16),
                    _buildTextField(
                      controller: _memoController,
                      label: 'メモ',
                      hint: '補足情報があれば記入',
                      icon: Icons.note_outlined,
                      required: false,
                      maxLines: 3,
                    ),
                    const SizedBox(height: 32),
                    SizedBox(
                      height: 48,
                      child: ElevatedButton.icon(
                        icon: Icon(Icons.send),
                        label: const Text('送信する'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Theme.of(context).colorScheme.primary,
                          foregroundColor: Colors.white,
                        ),
                        onPressed: _submit,
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    required bool required,
    int maxLines = 1,
  }) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, color: Theme.of(context).colorScheme.primary),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Theme.of(context).colorScheme.primary, width: 2),
        ),
      ),
      validator: required
          ? (v) => (v == null || v.trim().isEmpty) ? '$labelを入力してください' : null
          : null,
    );
  }
}
