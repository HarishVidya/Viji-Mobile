import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'booking_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Position? _currentPosition;
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _nearbySalons = [];
  bool _isLoading = true;
  static const double _searchRadiusKm = 5.0; // Search radius in kilometers

  @override
  void initState() {
    super.initState();
    _getCurrentLocation();
  }

  Future<void> _getCurrentLocation() async {
    setState(() {
      _isLoading = true;
    });

    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      
      if (permission == LocationPermission.whileInUse ||
          permission == LocationPermission.always) {
        Position position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
        );
        setState(() {
          _currentPosition = position;
        });
        await _fetchNearbySalons();
      } else {
        throw Exception('Location permission denied');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error getting location: ${e.toString()}')),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  // Calculate distance between two points using the coordinates
  double _calculateDistance(double salonLat, double salonLng) {
    if (_currentPosition == null) return double.infinity;

    return Geolocator.distanceBetween(
      _currentPosition!.latitude,
      _currentPosition!.longitude,
      salonLat,
      salonLng,
    ) / 1000; // Convert meters to kilometers
  }

  Future<void> _fetchNearbySalons() async {
    if (_currentPosition == null) return;

    try {
      // First, get all salons
      final QuerySnapshot<Map<String, dynamic>> snapshot = 
          await FirebaseFirestore.instance.collection('shops').get();

      // Filter salons based on distance
      List<QueryDocumentSnapshot<Map<String, dynamic>>> nearbySalons = [];
      
      for (var doc in snapshot.docs) {
        final double? latitude = (doc['lat'] as num?)?.toDouble();
        final double? longitude = (doc['lng'] as num?)?.toDouble();
        
        if (latitude != null && longitude != null) {
          double distance = _calculateDistance(latitude, longitude);
          if (distance <= _searchRadiusKm) {
            nearbySalons.add(doc);
          }
        }
      }

      // Sort by distance
      nearbySalons.sort((a, b) {
        final distanceA = _calculateDistance(
          (a['lat'] as num).toDouble(),
          (a['lng'] as num).toDouble(),
        );
        final distanceB = _calculateDistance(
          (b['lat'] as num).toDouble(),
          (b['lng'] as num).toDouble(),
        );
        return distanceA.compareTo(distanceB);
      });

      setState(() {
        _nearbySalons = nearbySalons;
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error fetching salons: ${e.toString()}')),
      );
    }
  }

  String _getOpenStatus(Map<String, dynamic> salon) {
    try {
      final now = DateTime.now();
      final dayOfWeek = now.weekday; // 1 = Monday, 7 = Sunday
      final currentTime = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
      
      final hours = salon['openingHours'] as Map<String, dynamic>?;
      if (hours == null) return 'Hours not available';

      final todayHours = hours[dayOfWeek.toString()] as Map<String, dynamic>?;
      if (todayHours == null) return 'Closed';

      final openTime = todayHours['open'] as String;
      final closeTime = todayHours['close'] as String;

      if (currentTime.compareTo(openTime) >= 0 && 
          currentTime.compareTo(closeTime) < 0) {
        return 'Open';
      } else {
        return 'Closed';
      }
    } catch (e) {
      return 'Hours not available';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nearby Salons'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _getCurrentLocation,
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => FirebaseAuth.instance.signOut(),
          ),
        ],
      ),
      body: _isLoading 
          ? const Center(child: CircularProgressIndicator())
          : _nearbySalons.isEmpty 
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.location_off, size: 64, color: Colors.grey),
                      const SizedBox(height: 16),
                      Text(
                        'No salons found within ${_searchRadiusKm}km',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: _getCurrentLocation,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Refresh'),
                      ),
                    ],
                  ),
                )
              : GridView.builder(
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 400,
                    childAspectRatio: 3 / 2,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                  ),
                  padding: const EdgeInsets.all(16),
                  itemCount: _nearbySalons.length,
                  itemBuilder: (context, index) {
                    final salon = _nearbySalons[index];
                    final distance = _calculateDistance(
                      (salon['lat'] as num).toDouble(),
                      (salon['lng'] as num).toDouble(),
                    );
                    final openStatus = _getOpenStatus(salon.data());
                    
                    return Card(
                      elevation: 4,
                      child: InkWell(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => BookingScreen(salon: salon),
                            ),
                          );
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          salon['name'] as String,
                                          style: Theme.of(context).textTheme.titleLarge,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 4),
                                        Row(
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.symmetric(
                                                horizontal: 6,
                                                vertical: 2,
                                              ),
                                              decoration: BoxDecoration(
                                                color: openStatus == 'Open' 
                                                    ? Colors.green.withOpacity(0.1)
                                                    : Colors.red.withOpacity(0.1),
                                                borderRadius: BorderRadius.circular(4),
                                              ),
                                              child: Text(
                                                openStatus,
                                                style: TextStyle(
                                                  color: openStatus == 'Open' 
                                                      ? Colors.green
                                                      : Colors.red,
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Theme.of(context).primaryColor.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      '${distance.toStringAsFixed(1)}km',
                                      style: TextStyle(
                                        color: Theme.of(context).primaryColor,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                salon['address']['streetaddress'] as String,
                                style: Theme.of(context).textTheme.bodyMedium,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const Spacer(),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  // if (salon['rating'] != null)
                                  //   Row(
                                  //     children: [
                                  //       const Icon(Icons.star, 
                                  //         color: Colors.amber, 
                                  //         size: 20,
                                  //       ),
                                  //       const SizedBox(width: 4),
                                  //       Text(
                                  //         (salon['rating'] as num).toStringAsFixed(1),
                                  //         style: Theme.of(context).textTheme.bodyLarge,
                                  //       ),
                                  //     ],
                                  //   ),
                                  ElevatedButton.icon(
                                    onPressed: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) => BookingScreen(salon: salon),
                                        ),
                                      );
                                    },
                                    icon: const Icon(Icons.calendar_today),
                                    label: const Text('Book'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}