import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp();
    runApp(MyApp());
  } catch (e) {
    print('Firebase initialization error: $e');
    runApp(ErrorApp());
  }
}

class ErrorApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error, size: 64, color: Colors.red),
              SizedBox(height: 16),
              Text('Failed to initialize Firebase'),
              ElevatedButton(
                onPressed: () => main(),
                child: Text('Retry'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class AuthService {
  static final FirebaseAuth _auth = FirebaseAuth.instance;
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Sign up with email, password, and username
  static Future<User?> signUpWithEmailPassword({
    required String email,
    required String password,
    required String username,
  }) async {
    try {
      if (email.trim().isEmpty || password.trim().isEmpty || username.trim().isEmpty) {
        throw Exception('All fields are required');
      }

      if (password.length < 6) {
        throw Exception('Password must be at least 6 characters');
      }

      if (!_isValidEmail(email)) {
        throw Exception('Please enter a valid email address');
      }

      // Check if username is already taken
      final usernameQuery = await _firestore
          .collection('users')
          .where('username', isEqualTo: username.trim().toLowerCase())
          .get();

      if (usernameQuery.docs.isNotEmpty) {
        throw Exception('Username is already taken');
      }

      // Create user with email and password
      final UserCredential userCredential = await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );

      final User? user = userCredential.user;

      if (user != null) {
        // Update display name
        await user.updateDisplayName(username.trim());

        // Save user data to Firestore
        await _saveUserToFirestore(user, username.trim());

        // Send email verification
        if (!user.emailVerified) {
          await user.sendEmailVerification();
        }
      }

      return user;
    } on FirebaseAuthException catch (e) {
      print('Firebase Auth Error: ${e.code} - ${e.message}');
      throw _getReadableAuthError(e);
    } catch (e) {
      print('Sign Up Error: $e');
      if (e.toString().contains('Exception:')) {
        rethrow;
      }
      throw Exception('Failed to create account. Please try again.');
    }
  }

  // Sign in with email and password
  static Future<User?> signInWithEmailPassword({
    required String email,
    required String password,
  }) async {
    try {
      if (email.trim().isEmpty || password.trim().isEmpty) {
        throw Exception('Email and password are required');
      }

      final UserCredential userCredential = await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );

      final User? user = userCredential.user;

      if (user != null) {
        // Update last seen
        await _updateUserLastSeen(user.uid);
      }

      return user;
    } on FirebaseAuthException catch (e) {
      print('Firebase Auth Error: ${e.code} - ${e.message}');
      throw _getReadableAuthError(e);
    } catch (e) {
      print('Sign In Error: $e');
      if (e.toString().contains('Exception:')) {
        rethrow;
      }
      throw Exception('Failed to sign in. Please try again.');
    }
  }

  // Reset password
  static Future<void> resetPassword(String email) async {
    try {
      if (email.trim().isEmpty) {
        throw Exception('Email is required');
      }

      if (!_isValidEmail(email)) {
        throw Exception('Please enter a valid email address');
      }

      await _auth.sendPasswordResetEmail(email: email.trim());
    } on FirebaseAuthException catch (e) {
      print('Password Reset Error: ${e.code} - ${e.message}');
      throw _getReadableAuthError(e);
    } catch (e) {
      print('Password Reset Error: $e');
      if (e.toString().contains('Exception:')) {
        rethrow;
      }
      throw Exception('Failed to send password reset email.');
    }
  }

  // Save user to Firestore
  static Future<void> _saveUserToFirestore(User user, String username) async {
    try {
      final userData = {
        'uid': user.uid,
        'username': username.toLowerCase(),
        'displayName': username,
        'email': user.email ?? '',
        'emailVerified': user.emailVerified,
        'createdAt': FieldValue.serverTimestamp(),
        'lastSeen': FieldValue.serverTimestamp(),
        'isOnline': true,
      };

      await _firestore.collection('users').doc(user.uid).set(userData);
    } catch (e) {
      print('Error saving user to Firestore: $e');
      throw Exception('Failed to save user data');
    }
  }

  // Update user last seen
  static Future<void> _updateUserLastSeen(String uid) async {
    try {
      await _firestore.collection('users').doc(uid).update({
        'lastSeen': FieldValue.serverTimestamp(),
        'isOnline': true,
      });
    } catch (e) {
      print('Error updating last seen: $e');
      // Don't throw here as it's not critical
    }
  }

  // Update user offline status
  static Future<void> _updateUserOfflineStatus(String uid) async {
    try {
      await _firestore.collection('users').doc(uid).update({
        'lastSeen': FieldValue.serverTimestamp(),
        'isOnline': false,
      });
    } catch (e) {
      print('Error updating offline status: $e');
    }
  }

  // Sign out
  static Future<void> signOut() async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser != null) {
        await _updateUserOfflineStatus(currentUser.uid);
      }
      await _auth.signOut();
    } catch (e) {
      print('Sign out error: $e');
      // Force sign out even if there's an error
      await _auth.signOut();
    }
  }

  // Check if username is available
  static Future<bool> isUsernameAvailable(String username) async {
    try {
      final query = await _firestore
          .collection('users')
          .where('username', isEqualTo: username.trim().toLowerCase())
          .get();
      return query.docs.isEmpty;
    } catch (e) {
      print('Error checking username availability: $e');
      return false;
    }
  }

  // Email validation
  static bool _isValidEmail(String email) {
    return RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(email);
  }

  // Get readable auth error messages
  static String _getReadableAuthError(FirebaseAuthException e) {
    switch (e.code) {
      case 'user-not-found':
        return 'No user found with this email address.';
      case 'wrong-password':
        return 'Incorrect password.';
      case 'invalid-email':
        return 'Please enter a valid email address.';
      case 'user-disabled':
        return 'This user account has been disabled.';
      case 'too-many-requests':
        return 'Too many attempts. Please try again later.';
      case 'email-already-in-use':
        return 'An account already exists with this email address.';
      case 'weak-password':
        return 'Password is too weak. Use at least 6 characters.';
      case 'network-request-failed':
        return 'Network error. Please check your connection.';
      case 'requires-recent-login':
        return 'Please sign in again to perform this action.';
      default:
        return e.message ?? 'An authentication error occurred.';
    }
  }
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Firebase Chat',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: AuthWrapper(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class AuthWrapper extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return LoadingScreen();
        }

        if (snapshot.hasError) {
          return ErrorScreen(
            message: 'Authentication error occurred',
            onRetry: () => Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => AuthWrapper()),
            ),
          );
        }

        if (snapshot.hasData && snapshot.data != null) {
          return UserListScreen();
        }

        return AuthScreen();
      },
    );
  }
}

class LoadingScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Loading...'),
          ],
        ),
      ),
    );
  }
}

class ErrorScreen extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;

  const ErrorScreen({
    Key? key,
    required this.message,
    this.onRetry,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error, size: 64, color: Colors.red),
              SizedBox(height: 16),
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16),
              ),
              if (onRetry != null) ...[
                SizedBox(height: 16),
                ElevatedButton(
                  onPressed: onRetry,
                  child: Text('Retry'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class AuthScreen extends StatefulWidget {
  @override
  _AuthScreenState createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final PageController _pageController = PageController();
  final _formKey = GlobalKey<FormState>();

  // Controllers
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _usernameController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _isLoading = false;
  bool _isSignUp = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  String? _errorMessage;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _usernameController.dispose();
    _confirmPasswordController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  void _toggleAuthMode() {
    setState(() {
      _isSignUp = !_isSignUp;
      _errorMessage = null;
    });
    _pageController.animateToPage(
      _isSignUp ? 1 : 0,
      duration: Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  Future<void> _signIn() async {
    if (!_formKey.currentState!.validate() || _isLoading) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await AuthService.signInWithEmailPassword(
        email: _emailController.text,
        password: _passwordController.text,
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString().replaceAll('Exception: ', '');
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _signUp() async {
    if (!_formKey.currentState!.validate() || _isLoading) return;

    if (_passwordController.text != _confirmPasswordController.text) {
      setState(() {
        _errorMessage = 'Passwords do not match';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await AuthService.signUpWithEmailPassword(
        email: _emailController.text,
        password: _passwordController.text,
        username: _usernameController.text,
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString().replaceAll('Exception: ', '');
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _resetPassword() async {
    if (_emailController.text.trim().isEmpty) {
      setState(() {
        _errorMessage = 'Please enter your email address';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await AuthService.resetPassword(_emailController.text);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Password reset email sent!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString().replaceAll('Exception: ', '');
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            children: [
              // Header
              Expanded(
                flex: 2,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.chat_bubble_outline,
                      size: 80,
                      color: Theme.of(context).primaryColor,
                    ),
                    SizedBox(height: 16),
                    Text(
                      'Welcome to Chat App',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      _isSignUp
                          ? 'Create an account to get started'
                          : 'Sign in to continue chatting',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),

              // Form
              Expanded(
                flex: 3,
                child: PageView(
                  controller: _pageController,
                  onPageChanged: (index) {
                    setState(() {
                      _isSignUp = index == 1;
                      _errorMessage = null;
                    });
                  },
                  children: [
                    _buildSignInForm(),
                    _buildSignUpForm(),
                  ],
                ),
              ),

              // Toggle button
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    _isSignUp
                        ? 'Already have an account? '
                        : "Don't have an account? ",
                  ),
                  TextButton(
                    onPressed: _toggleAuthMode,
                    child: Text(_isSignUp ? 'Sign In' : 'Sign Up'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSignInForm() {
    return Form(
      key: _formKey,
      child: Column(
        children: [
          TextFormField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            decoration: InputDecoration(
              labelText: 'Email',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.email),
            ),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Email is required';
              }
              if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(value)) {
                return 'Please enter a valid email';
              }
              return null;
            },
          ),
          SizedBox(height: 16),
          TextFormField(
            controller: _passwordController,
            obscureText: _obscurePassword,
            decoration: InputDecoration(
              labelText: 'Password',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.lock),
              suffixIcon: IconButton(
                icon: Icon(_obscurePassword ? Icons.visibility : Icons.visibility_off),
                onPressed: () {
                  setState(() {
                    _obscurePassword = !_obscurePassword;
                  });
                },
              ),
            ),
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Password is required';
              }
              return null;
            },
          ),
          SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: _isLoading ? null : _resetPassword,
              child: Text('Forgot Password?'),
            ),
          ),
          SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _signIn,
              style: ElevatedButton.styleFrom(
                padding: EdgeInsets.symmetric(vertical: 16),
              ),
              child: _isLoading
                  ? SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
                  : Text('Sign In'),
            ),
          ),
          if (_errorMessage != null) ...[
            SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red[50],
                border: Border.all(color: Colors.red[300]!),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _errorMessage!,
                style: TextStyle(color: Colors.red[700]),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSignUpForm() {
    return Form(
      key: _formKey,
      child: Column(
        children: [
          TextFormField(
            controller: _usernameController,
            decoration: InputDecoration(
              labelText: 'Username',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.person),
            ),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Username is required';
              }
              if (value.trim().length < 3) {
                return 'Username must be at least 3 characters';
              }
              if (!RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(value.trim())) {
                return 'Username can only contain letters, numbers, and underscores';
              }
              return null;
            },
          ),
          SizedBox(height: 16),
          TextFormField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            decoration: InputDecoration(
              labelText: 'Email',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.email),
            ),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Email is required';
              }
              if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(value)) {
                return 'Please enter a valid email';
              }
              return null;
            },
          ),
          SizedBox(height: 16),
          TextFormField(
            controller: _passwordController,
            obscureText: _obscurePassword,
            decoration: InputDecoration(
              labelText: 'Password',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.lock),
              suffixIcon: IconButton(
                icon: Icon(_obscurePassword ? Icons.visibility : Icons.visibility_off),
                onPressed: () {
                  setState(() {
                    _obscurePassword = !_obscurePassword;
                  });
                },
              ),
            ),
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Password is required';
              }
              if (value.length < 6) {
                return 'Password must be at least 6 characters';
              }
              return null;
            },
          ),
          SizedBox(height: 16),
          TextFormField(
            controller: _confirmPasswordController,
            obscureText: _obscureConfirmPassword,
            decoration: InputDecoration(
              labelText: 'Confirm Password',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.lock_outline),
              suffixIcon: IconButton(
                icon: Icon(_obscureConfirmPassword ? Icons.visibility : Icons.visibility_off),
                onPressed: () {
                  setState(() {
                    _obscureConfirmPassword = !_obscureConfirmPassword;
                  });
                },
              ),
            ),
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Please confirm your password';
              }
              return null;
            },
          ),
          SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _signUp,
              style: ElevatedButton.styleFrom(
                padding: EdgeInsets.symmetric(vertical: 16),
              ),
              child: _isLoading
                  ? SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
                  : Text('Sign Up'),
            ),
          ),
          if (_errorMessage != null) ...[
            SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red[50],
                border: Border.all(color: Colors.red[300]!),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _errorMessage!,
                style: TextStyle(color: Colors.red[700]),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class UserListScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;

    if (currentUser == null) {
      return AuthScreen();
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('Chats'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) async {
              if (value == 'signout') {
                await AuthService.signOut();
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'signout',
                child: Row(
                  children: [
                    Icon(Icons.logout),
                    SizedBox(width: 8),
                    Text('Sign Out'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .where('uid', isNotEqualTo: currentUser.uid)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return ErrorScreen(
              message: 'Error loading users: ${snapshot.error}',
              onRetry: () => Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (context) => UserListScreen()),
              ),
            );
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.people_outline, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text(
                    'No other users found',
                    style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                  ),
                ],
              ),
            );
          }

          final users = snapshot.data!.docs;

          return ListView.builder(
            itemCount: users.length,
            itemBuilder: (context, index) {
              final user = users[index];
              final userData = user.data() as Map<String, dynamic>;

              return Card(
                margin: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Theme.of(context).primaryColor,
                    child: Text(
                      (userData['displayName']?.toString() ??
                          userData['username']?.toString() ??
                          'U')[0].toUpperCase(),
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  title: Text(
                    userData['displayName']?.toString() ??
                        userData['username']?.toString() ??
                        'Unknown User',
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(userData['email']?.toString() ?? ''),
                      SizedBox(height: 2),
                      Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: userData['isOnline'] == true
                                  ? Colors.green
                                  : Colors.grey,
                            ),
                          ),
                          SizedBox(width: 4),
                          Text(
                            userData['isOnline'] == true ? 'Online' : 'Offline',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  isThreeLine: true,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => ChatScreen(
                          otherUser: user,
                          otherUserData: userData,
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class ChatScreen extends StatefulWidget {
  final DocumentSnapshot otherUser;
  final Map<String, dynamic> otherUserData;

  const ChatScreen({
    Key? key,
    required this.otherUser,
    required this.otherUserData,
  }) : super(key: key);

  @override
  _ChatScreenState createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isLoading = false;

  User? get currentUser => FirebaseAuth.instance.currentUser;

  String get chatId {
    if (currentUser == null) return '';
    final ids = [currentUser!.uid, widget.otherUser['uid']];
    ids.sort();
    return ids.join('_');
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _sendMessage() async {
    if (_controller.text.trim().isEmpty || _isLoading || currentUser == null) {
      return;
    }

    final messageText = _controller.text.trim();
    _controller.clear();

    setState(() {
      _isLoading = true;
    });

    try {
      await FirebaseFirestore.instance
          .collection('chats')
          .doc(chatId)
          .collection('messages')
          .add({
        'text': messageText,
        'senderId': currentUser!.uid,
        'senderName': currentUser!.displayName ?? 'Unknown',
        'createdAt': FieldValue.serverTimestamp(),
      });

      // Update chat metadata
      await FirebaseFirestore.instance
          .collection('chats')
          .doc(chatId)
          .set({
        'participants': [currentUser!.uid, widget.otherUser['uid']],
        'participantNames': {
          currentUser!.uid: currentUser!.displayName ?? 'Unknown',
          widget.otherUser['uid']: widget.otherUserData['displayName'] ?? 'Unknown',
        },
        'lastMessage': messageText,
        'lastMessageTime': FieldValue.serverTimestamp(),
        'lastMessageSender': currentUser!.uid,
      }, SetOptions(merge: true));

    } catch (e) {
      print('Error sending message: $e');
      // Show error to user
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to send message. Please try again.'),
          backgroundColor: Colors.red,
        ),
      );
      // Restore message text
      _controller.text = messageText;
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (currentUser == null) {
      return AuthScreen();
    }

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: Theme.of(context).primaryColor,
              child: Text(
                (widget.otherUserData['displayName']?.toString() ??
                    widget.otherUserData['username']?.toString() ??
                    'U')[0].toUpperCase(),
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
            SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.otherUserData['displayName']?.toString() ??
                        widget.otherUserData['username']?.toString() ??
                        'Unknown User',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 16),
                  ),
                  Text(
                    widget.otherUserData['isOnline'] == true ? 'Online' : 'Offline',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('chats')
                  .doc(chatId)
                  .collection('messages')
                  .orderBy('createdAt', descending: true)
                  .limit(50) // Limit for performance
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.error, size: 48, color: Colors.red),
                        SizedBox(height: 16),
                        Text('Error loading messages'),
                        ElevatedButton(
                          onPressed: () => setState(() {}),
                          child: Text('Retry'),
                        ),
                      ],
                    ),
                  );
                }

                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.chat_bubble_outline,
                            size: 48,
                            color: Colors.grey),
                        SizedBox(height: 16),
                        Text(
                          'No messages yet',
                          style: TextStyle(color: Colors.grey[600]),
                        ),
                        Text(
                          'Start a conversation!',
                          style: TextStyle(color: Colors.grey[600]),
                        ),
                      ],
                    ),
                  );
                }

                final messages = snapshot.data!.docs;

                return ListView.builder(
                  controller: _scrollController,
                  reverse: true,
                  itemCount: messages.length,
                  padding: EdgeInsets.symmetric(vertical: 8),
                  itemBuilder: (context, index) {
                    final message = messages[index];
                    final messageData = message.data() as Map<String, dynamic>;
                    final isMe = messageData['senderId'] == currentUser!.uid;
                    final timestamp = messageData['createdAt'] as Timestamp?;

                    return Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 2,
                      ),
                      child: Row(
                        mainAxisAlignment: isMe
                            ? MainAxisAlignment.end
                            : MainAxisAlignment.start,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (!isMe) ...[
                            CircleAvatar(
                              radius: 12,
                              backgroundColor: Theme.of(context).primaryColor.withOpacity(0.3),
                              child: Text(
                                (messageData['senderName']?.toString() ?? 'U')[0].toUpperCase(),
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            SizedBox(width: 8),
                          ],
                          Container(
                            constraints: BoxConstraints(
                              maxWidth: MediaQuery.of(context).size.width * 0.7,
                            ),
                            padding: EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: isMe
                                  ? Theme.of(context).primaryColor
                                  : Colors.grey[300],
                              borderRadius: BorderRadius.only(
                                topLeft: Radius.circular(16),
                                topRight: Radius.circular(16),
                                bottomLeft: isMe ? Radius.circular(16) : Radius.circular(4),
                                bottomRight: isMe ? Radius.circular(4) : Radius.circular(16),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (!isMe)
                                  Padding(
                                    padding: EdgeInsets.only(bottom: 2),
                                    child: Text(
                                      messageData['senderName']?.toString() ?? 'Unknown',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.grey[700],
                                      ),
                                    ),
                                  ),
                                Text(
                                  messageData['text'] ?? '',
                                  style: TextStyle(
                                    color: isMe ? Colors.white : Colors.black87,
                                    fontSize: 16,
                                  ),
                                ),
                                if (timestamp != null) ...[
                                  SizedBox(height: 2),
                                  Text(
                                    _formatTimestamp(timestamp),
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: isMe
                                          ? Colors.white70
                                          : Colors.grey[600],
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          if (isMe) ...[
                            SizedBox(width: 8),
                            CircleAvatar(
                              radius: 12,
                              backgroundColor: Theme.of(context).primaryColor.withOpacity(0.7),
                              child: Text(
                                (currentUser!.displayName ?? 'You')[0].toUpperCase(),
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
          Container(
            padding: EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).scaffoldBackgroundColor,
              border: Border(top: BorderSide(color: Colors.grey[300]!)),
            ),
            child: SafeArea(
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: TextField(
                        controller: _controller,
                        decoration: InputDecoration(
                          hintText: "Type a message...",
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                        ),
                        maxLines: null,
                        textCapitalization: TextCapitalization.sentences,
                        onSubmitted: (_) => _sendMessage(),
                        enabled: !_isLoading,
                      ),
                    ),
                  ),
                  SizedBox(width: 8),
                  Container(
                    decoration: BoxDecoration(
                      color: Theme.of(context).primaryColor,
                      shape: BoxShape.circle,
                    ),
                    child: _isLoading
                        ? Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.white,
                          ),
                        ),
                      ),
                    )
                        : IconButton(
                      icon: Icon(Icons.send, color: Colors.white),
                      onPressed: _sendMessage,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatTimestamp(Timestamp timestamp) {
    final DateTime dateTime = timestamp.toDate();
    final DateTime now = DateTime.now();
    final Duration difference = now.difference(dateTime);

    if (difference.inDays > 7) {
      return '${dateTime.day}/${dateTime.month}/${dateTime.year}';
    } else if (difference.inDays > 0) {
      return '${difference.inDays}d ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}h ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}m ago';
    } else {
      return 'Just now';
    }
  }
}