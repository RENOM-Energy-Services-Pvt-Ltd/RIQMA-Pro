import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../screens/add_planning_screen.dart';

class PlanningTab extends StatefulWidget {
  const PlanningTab({super.key});

  @override
  State<PlanningTab> createState() => _PlanningTabState();
}

class _PlanningTabState extends State<PlanningTab> {
  final TextEditingController _searchController = TextEditingController();
  
  String _searchQuery = '';
  String? _selectedState;
  String? _selectedSite;
  String? _selectedModel;
  DateTimeRange? _selectedDateRange;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute<void>(builder: (context) => const AddPlanningScreen()),
          );
        },
        backgroundColor: const Color(0xFF00897B),
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: Column(
        children: [
          // Search Bar
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _searchController,
              onChanged: (val) => setState(() => _searchQuery = val),
              decoration: InputDecoration(
                hintText: 'Search',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
              ),
            ),
          ),
          
          // Filter Buttons
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('planning_data').snapshots(),
              builder: (context, snapshot) {
                final docs = snapshot.data?.docs ?? [];
                
                return Row(
                  children: [
                    _buildFilterButton(
                      'State', 
                      _selectedState, 
                      () => _showFilterDialog('State', docs, 'state', (val) => setState(() => _selectedState = val))
                    ),
                    const SizedBox(width: 8),
                    _buildFilterButton(
                      'Site', 
                      _selectedSite, 
                      () => _showFilterDialog('Site', docs, 'site_name', (val) => setState(() => _selectedSite = val))
                    ),
                    const SizedBox(width: 8),
                    _buildFilterButton(
                      'WTG Model', 
                      _selectedModel, 
                      () => _showFilterDialog('WTG Model', docs, 'turbine_model', (val) => setState(() => _selectedModel = val))
                    ),
                    const SizedBox(width: 8),
                    _buildDateFilterButton(),
                  ],
                );
              }
            ),
          ),
          
          const SizedBox(height: 16),

          // List of Plans
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('planning_data')
                  .orderBy('planned_date', descending: false)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final docs = snapshot.data!.docs;

                // Apply Filters
                final filteredDocs = docs.where((doc) {
                   final data = doc.data() as Map<String, dynamic>;
                   
                   // 1. Search Filter
                   final searchLower = _searchQuery.toLowerCase();
                   final siteName = (data['site_name'] ?? '').toString().toLowerCase();
                   final model = (data['turbine_model'] ?? '').toString().toLowerCase();
                   final state = (data['state'] ?? '').toString().toLowerCase();
                   
                   final matchesSearch = siteName.contains(searchLower) || 
                                        model.contains(searchLower) || 
                                        state.contains(searchLower);
                   
                   // 2. Chip Filters
                   final matchesState = _selectedState == null || data['state'] == _selectedState;
                   final matchesSite = _selectedSite == null || data['site_name'] == _selectedSite;
                   final matchesModel = _selectedModel == null || data['turbine_model'] == _selectedModel;
                   
                   // 3. Date Filter
                   var matchesDate = true;
                   if (_selectedDateRange != null && data['planned_date'] != null) {
                     final date = (data['planned_date'] as Timestamp).toDate();
                     matchesDate = date.isAfter(_selectedDateRange!.start.subtract(const Duration(days: 1))) && 
                                   date.isBefore(_selectedDateRange!.end.add(const Duration(days: 1)));
                   }

                   return matchesSearch && matchesState && matchesSite && matchesModel && matchesDate;
                }).toList();

                if (filteredDocs.isEmpty) {
                  return const Center(child: Text('No plans found'));
                }

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  itemCount: filteredDocs.length,
                  itemBuilder: (context, index) {
                    return _buildPlanCard(filteredDocs[index]);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterButton(String label, String? selectedValue, VoidCallback onTap) {
    final isSelected = selectedValue != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF00897B).withValues(alpha: 0.1) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? const Color(0xFF00897B) : Colors.grey[300]!
          ),
        ),
        child: Row(
          children: [
            Text(
              isSelected ? selectedValue : label, 
              style: TextStyle(
                color: isSelected ? const Color(0xFF00897B) : Colors.black87,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              )
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.arrow_drop_down, 
              color: isSelected ? const Color(0xFF00897B) : Colors.grey
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDateFilterButton() {
    final isSelected = _selectedDateRange != null;
    var label = 'Date';
    if (isSelected) {
      label = '${DateFormat('MMM d').format(_selectedDateRange!.start)} - ${DateFormat('MMM d').format(_selectedDateRange!.end)}';
    }

    return GestureDetector(
      onTap: _selectDateRange,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF00897B).withValues(alpha: 0.1) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? const Color(0xFF00897B) : Colors.grey[300]!
          ),
        ),
        child: Row(
          children: [
            Text(
              label, 
              style: TextStyle(
                color: isSelected ? const Color(0xFF00897B) : Colors.black87,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              )
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.calendar_today, 
              size: 16,
              color: isSelected ? const Color(0xFF00897B) : Colors.grey
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _selectDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      initialDateRange: _selectedDateRange,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF00897B),
              onPrimary: Colors.white,
              onSurface: Colors.black,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _selectedDateRange = picked;
      });
    } else if (_selectedDateRange != null) {
      // Allow clearing date filter if opened and cancelled? 
      // Or maybe add a clear button in the picker?
      // For now, let's add a way to clear in the dialog logic or just keep it simple.
      // To clear, user can tap the active filter and we can show a dialog or just toggle.
      // Let's keep it simple: if they cancel, do nothing. 
      // To clear, we might need a "Clear" button in the UI or logic.
      // Let's add a long press to clear or just tap again to clear?
      // For better UX, let's show a bottom sheet for date options including "Clear".
    }
  }

  void _showFilterDialog(String title, List<QueryDocumentSnapshot> docs, String field, void Function(String?) onSelect) {
    // Extract unique values
    final values = <String>{};
    for (var doc in docs) {
      final data = doc.data() as Map<String, dynamic>;
      if (data[field] != null) {
        values.add(data[field].toString());
      }
    }
    final sortedValues = values.toList()..sort();

    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Select $title',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              ListTile(
                leading: const Icon(Icons.clear_all),
                title: const Text('Clear Filter'),
                onTap: () {
                  onSelect(null);
                  Navigator.pop(context);
                },
              ),
              const Divider(),
              Expanded(
                child: ListView.builder(
                  itemCount: sortedValues.length,
                  itemBuilder: (context, index) {
                    final value = sortedValues[index];
                    return ListTile(
                      title: Text(value),
                      onTap: () {
                        onSelect(value);
                        Navigator.pop(context);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }


  Widget _buildPlanCard(QueryDocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    
    final siteName = data['site_name'] ?? 'Unknown Site';
    final turbineModel = data['turbine_model'] ?? 'Unknown Model';
    
    String mainDisplay;
    if (data.containsKey('number_of_turbines')) {
      mainDisplay = '${data['number_of_turbines']} Turbines';
    } else {
      mainDisplay = (data['turbine_id'] as String?) ?? 'Unknown ID';
    }

    // Status Logic
    final status = (data['status'] as String?) ?? 'pending_approval'; // Default to pending if missing
    
    // Normalize status for display and logic
    final isApproved = status == 'approved' || status == 'Planned'; // 'Planned' is legacy for Approved
    final isCompleted = status == 'completed';

    String statusText;
    Color statusColor;
    Color statusBgColor;

    if (isCompleted) {
      statusText = 'Completed';
      statusColor = Colors.green[800]!;
      statusBgColor = Colors.green[50]!;
    } else if (isApproved) {
      statusText = 'Approved';
      statusColor = Colors.blue[800]!;
      statusBgColor = Colors.blue[50]!;
    } else {
      // Pending
      statusText = 'Pending Approval';
      statusColor = Colors.orange[800]!;
      statusBgColor = Colors.orange[50]!;
    }

    final auditors = (data['auditors'] as List<dynamic>?)?.join(', ') ?? 'No Auditors';
    
    DateTime? date;
    if (data['planned_date'] != null) {
      date = (data['planned_date'] as Timestamp).toDate();
    }
    final dateStr = date != null ? DateFormat('dd MMM yyyy').format(date) : 'No Date';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isCompleted ? const BorderSide(color: Colors.green, width: 2) : BorderSide.none,
      ),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    '$siteName / $turbineModel',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusBgColor,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: statusColor.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    statusText,
                    style: TextStyle(
                      color: statusColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              mainDisplay,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: isCompleted ? Colors.green[700] : const Color(0xFF00897B),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.calendar_today, size: 16, color: Colors.grey),
                const SizedBox(width: 4),
                Text(dateStr, style: const TextStyle(color: Colors.grey)),
                const SizedBox(width: 16),
                const Icon(Icons.person_outline, size: 16, color: Colors.grey),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    auditors,
                    style: const TextStyle(color: Colors.grey),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
