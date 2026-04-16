import 'package:flutter/material.dart';

/// A modern, searchable dropdown widget with smooth animations and glass effect.
class SearchableDropdown<T> extends StatefulWidget {
  final List<SearchableDropdownItem<T>> items;
  final T? selectedValue;
  final ValueChanged<T?>? onChanged;
  final String labelText;
  final String hintText;
  final String? disabledHint;
  final bool enabled;
  final IconData? prefixIcon;

  const SearchableDropdown({
    required this.items, super.key,
    this.selectedValue,
    this.onChanged,
    this.labelText = '',
    this.hintText = 'Search...',
    this.disabledHint,
    this.enabled = true,
    this.prefixIcon,
  });

  @override
  State<SearchableDropdown<T>> createState() => _SearchableDropdownState<T>();
}

class _SearchableDropdownState<T> extends State<SearchableDropdown<T>> {
  String? _displayText;

  @override
  void initState() {
    super.initState();
    _updateDisplayText();
  }

  @override
  void didUpdateWidget(covariant SearchableDropdown<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedValue != widget.selectedValue ||
        oldWidget.items != widget.items) {
      _updateDisplayText();
    }
  }

  void _updateDisplayText() {
    if (widget.selectedValue != null) {
      final selectedItem = widget.items.firstWhere(
        (item) => item.value == widget.selectedValue,
        orElse: () => SearchableDropdownItem<T>(value: widget.selectedValue as T, label: ''),
      );
      _displayText = selectedItem.label;
    } else {
      _displayText = null;
    }
  }

  void _showSearchDialog() {
    showDialog<T>(
      context: context,
      builder: (context) => _SearchDialog<T>(
        items: widget.items,
        selectedValue: widget.selectedValue,
        hintText: widget.hintText,
        labelText: widget.labelText,
      ),
    ).then((value) {
      if (value != null) {
        widget.onChanged?.call(value);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDisabled = !widget.enabled || widget.onChanged == null;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      child: Material(
        elevation: isDisabled ? 0 : 2,
        shadowColor: const Color(0xFF00897B).withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: isDisabled ? null : _showSearchDialog,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              gradient: isDisabled
                  ? null
                  : LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Colors.white,
                        Colors.grey.shade50,
                      ],
                    ),
              color: isDisabled ? Colors.grey.shade200 : null,
              border: Border.all(
                color: isDisabled
                    ? Colors.grey.shade300
                    : widget.selectedValue != null
                        ? const Color(0xFF00897B)
                        : Colors.grey.shade400,
                width: widget.selectedValue != null ? 1.5 : 1,
              ),
            ),
            child: Row(
              children: [
                if (widget.prefixIcon != null) ...[
                  Icon(
                    widget.prefixIcon,
                    color: isDisabled
                        ? Colors.grey
                        : widget.selectedValue != null
                            ? const Color(0xFF00897B)
                            : Colors.grey.shade600,
                    size: 22,
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (widget.labelText.isNotEmpty)
                        Text(
                          widget.labelText,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: isDisabled
                                ? Colors.grey
                                : const Color(0xFF00897B),
                            letterSpacing: 0.5,
                          ),
                        ),
                      const SizedBox(height: 2),
                      Text(
                        isDisabled
                            ? (widget.disabledHint ?? 'Not available')
                            : (_displayText ?? widget.hintText),
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: _displayText != null
                              ? FontWeight.w600
                              : FontWeight.normal,
                          color: isDisabled
                              ? Colors.grey
                              : _displayText != null
                                  ? Colors.black87
                                  : Colors.grey.shade500,
                        ),
                      ),
                    ],
                  ),
                ),
                AnimatedRotation(
                  turns: 0,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(
                    Icons.keyboard_arrow_down_rounded,
                    color: isDisabled ? Colors.grey : Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SearchDialog<T> extends StatefulWidget {
  final List<SearchableDropdownItem<T>> items;
  final T? selectedValue;
  final String hintText;
  final String labelText;

  const _SearchDialog({
    required this.items,
    this.selectedValue,
    this.hintText = 'Search...',
    this.labelText = '',
  });

  @override
  State<_SearchDialog<T>> createState() => _SearchDialogState<T>();
}

class _SearchDialogState<T> extends State<_SearchDialog<T>> {
  late TextEditingController _searchController;
  late List<SearchableDropdownItem<T>> _filteredItems;
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _filteredItems = widget.items;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _filterItems(String query) {
    setState(() {
      if (query.isEmpty) {
        _filteredItems = widget.items;
      } else {
        _filteredItems = widget.items.where((item) {
          return item.label.toLowerCase().contains(query.toLowerCase()) ||
              (item.subtitle?.toLowerCase().contains(query.toLowerCase()) ?? false);
        }).toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.7,
          maxWidth: 500,
        ),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 30,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFF00897B),
                    Color(0xFF00695C),
                  ],
                ),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.search_rounded,
                        color: Colors.white70,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Select ${widget.labelText}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close, color: Colors.white70),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Search Field
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: TextField(
                      controller: _searchController,
                      focusNode: _focusNode,
                      onChanged: _filterItems,
                      style: const TextStyle(color: Colors.white),
                      cursorColor: Colors.white,
                      decoration: InputDecoration(
                        hintText: widget.hintText,
                        hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
                        prefixIcon: Icon(
                          Icons.search,
                          color: Colors.white.withValues(alpha: 0.7),
                        ),
                        suffixIcon: _searchController.text.isNotEmpty
                            ? IconButton(
                                icon: Icon(
                                  Icons.clear,
                                  color: Colors.white.withValues(alpha: 0.7),
                                ),
                                onPressed: () {
                                  _searchController.clear();
                                  _filterItems('');
                                },
                              )
                            : null,
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Results count
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              color: Colors.grey.shade50,
              child: Row(
                children: [
                  Text(
                    '${_filteredItems.length} items found',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            // Items List
            Flexible(
              child: _filteredItems.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.search_off_rounded,
                              size: 48,
                              color: Colors.grey.shade400,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'No results found',
                              style: TextStyle(
                                color: Colors.grey.shade600,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: _filteredItems.length,
                      separatorBuilder: (context, index) => Divider(
                        height: 1,
                        color: Colors.grey.shade200,
                        indent: 16,
                        endIndent: 16,
                      ),
                      itemBuilder: (context, index) {
                        final item = _filteredItems[index];
                        final isSelected = item.value == widget.selectedValue;
                        final isRecent = !isSelected && item.showRecentIndicator;

                        return Material(
                          color: isSelected
                              ? const Color(0xFF00897B).withValues(alpha: 0.08)
                              : isRecent
                                  ? Colors.amber.withValues(alpha: 0.05) // Subtle amber for in-progress
                                  : Colors.transparent,
                          child: InkWell(
                            onTap: () => Navigator.of(context).pop(item.value),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 14,
                              ),
                              child: Row(
                                children: [
                                  if (item.icon != null) ...[
                                    Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: isSelected
                                            ? const Color(0xFF00897B)
                                                .withValues(alpha: 0.15)
                                            : isRecent
                                                ? Colors.amber.withValues(alpha: 0.15)
                                                : Colors.grey.shade100,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Icon(
                                        isRecent ? Icons.hourglass_bottom_rounded : item.icon, // Pending icon
                                        size: 20,
                                        color: isSelected
                                            ? const Color(0xFF00897B)
                                            : isRecent
                                                ? Colors.amber.shade800
                                                : Colors.grey.shade600,
                                      ),
                                    ),
                                    const SizedBox(width: 14),
                                  ],
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          item.label,
                                          style: TextStyle(
                                            fontSize: 15,
                                            fontWeight: (isSelected || isRecent)
                                                ? FontWeight.w600
                                                : FontWeight.w500,
                                            color: isSelected
                                                ? const Color(0xFF00897B)
                                                : isRecent
                                                    ? Colors.amber.shade900
                                                    : Colors.black87,
                                          ),
                                        ),
                                        if (item.subtitle != null) ...[
                                          const SizedBox(height: 2),
                                          Text(
                                            item.subtitle!,
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: isRecent ? Colors.amber.shade700 : Colors.grey.shade600,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                  if (isSelected)
                                    Container(
                                      padding: const EdgeInsets.all(4),
                                      decoration: const BoxDecoration(
                                        color: Color(0xFF00897B),
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                        Icons.check,
                                        size: 14,
                                        color: Colors.white,
                                      ),
                                    ),
                                  if (isRecent)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.amber.withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(color: Colors.amber.shade300, width: 0.5),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            'PENDING',
                                            style: TextStyle(
                                              fontSize: 9,
                                              fontWeight: FontWeight.w900,
                                              color: Colors.amber.shade800,
                                              letterSpacing: 0.5,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Data class for searchable dropdown items
class SearchableDropdownItem<T> {
  final T value;
  final String label;
  final String? subtitle;
  final IconData? icon;
  final bool showRecentIndicator;

  const SearchableDropdownItem({
    required this.value,
    required this.label,
    this.subtitle,
    this.icon,
    this.showRecentIndicator = false,
  });
}
