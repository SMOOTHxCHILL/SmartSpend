import 'package:flutter/material.dart';
import '../models/category.dart';

/// Modal bottom sheet for picking a category. Pops the sheet with the
/// selected category string, or null if dismissed without a choice.
Future<String?> showCategoryPicker(
  BuildContext context, {
  required String currentCategory,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (context) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text(
                  'Set category',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const Divider(height: 1),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: Category.all.length,
                  itemBuilder: (context, index) {
                    final category = Category.all[index];
                    final isSelected = category == currentCategory;

                    return ListTile(
                      title: Text(category),
                      trailing: isSelected
                          ? const Icon(Icons.check, color: Colors.deepPurple)
                          : null,
                      onTap: () => Navigator.of(context).pop(category),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}