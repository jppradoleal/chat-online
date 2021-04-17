import 'dart:io';

import 'package:chat_online/widget/chat_message.dart';
import 'package:chat_online/widget/text_composer.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';

class Home extends StatefulWidget {
  final FirebaseFirestore firestore;
  final FirebaseStorage storage;
  final FirebaseAuth auth;

  Home(this.firestore, this.storage, this.auth);

  @override
  _HomeState createState() => _HomeState();
}

class _HomeState extends State<Home> {
  final GoogleSignIn googleSignIn = GoogleSignIn();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey();
  User _currentUser;

  bool _isLoading = false;

  @override
  void initState() {
    super.initState();

    widget.auth.authStateChanges().listen((user) {
      setState(() {
        _currentUser = user;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        title: Text(_currentUser != null
            ? "Olá, ${_currentUser.displayName}!"
            : "Chat App"),
        elevation: 0,
        actions: [
          _currentUser != null
              ? IconButton(
                  icon: Icon(Icons.exit_to_app),
                  onPressed: () {
                    widget.auth.signOut();
                    googleSignIn.signOut();

                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text("Você saiu com sucesso!"),
                    ));
                  },
                )
              : Container()
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder(
              stream: widget.firestore
                  .collection("messages")
                  .orderBy("createdAt")
                  .snapshots(),
              builder: (context, snapshot) {
                switch (snapshot.connectionState) {
                  case ConnectionState.none:
                  case ConnectionState.waiting:
                    return Center(child: CircularProgressIndicator());
                  default:
                    List<DocumentSnapshot> documents =
                        snapshot.data.docs.reversed.toList();
                    return ListView.builder(
                      itemCount: documents.length,
                      reverse: true,
                      itemBuilder: (context, index) {
                        return ChatMessage(
                            documents[index].data(),
                            _currentUser?.uid ==
                                documents[index].data()["uid"]);
                      },
                    );
                }
              },
            ),
          ),
          _isLoading ? LinearProgressIndicator() : Container(),
          TextComposer(_sendMessage),
        ],
      ),
    );
  }

  _sendMessage({text, File imgFile}) async {
    final User user = await _getUser();

    if (user == null) {
      ScaffoldMessenger.of(_scaffoldKey.currentContext).showSnackBar(
        SnackBar(
          content: Text("Não foi possivel fazer o login. Tente novamente."),
          backgroundColor: Colors.red,
        ),
      );
    }

    Map<String, dynamic> data = {
      "uid": user.uid,
      "senderName": user.displayName,
      "senderPhotoUrl": user.photoURL,
      "createdAt": Timestamp.now(),
    };

    if (imgFile != null) {
      setState(() {
        _isLoading = true;
      });

      TaskSnapshot snapshot = await widget.storage
          .ref()
          .child("files")
          .child(_currentUser.uid +
              DateTime.now().millisecondsSinceEpoch.toString())
          .putFile(imgFile);

      String url = await snapshot.ref.getDownloadURL();
      data['imgUrl'] = url;

      setState(() {
        _isLoading = false;
      });
    }

    if (text != null) data["text"] = text;

    await widget.firestore.collection("messages").doc().set(data);
  }

  Future<User> _getUser() async {
    if (_currentUser != null) return _currentUser;

    try {
      final GoogleSignInAccount googleSignInAccount =
          await googleSignIn.signIn();

      final GoogleSignInAuthentication googleSignInAuthentication =
          await googleSignInAccount.authentication;

      final AuthCredential credential = GoogleAuthProvider.credential(
          idToken: googleSignInAuthentication.idToken,
          accessToken: googleSignInAuthentication.accessToken);

      final UserCredential authResult =
          await widget.auth.signInWithCredential(credential);

      return authResult.user;
    } catch (e) {
      return null;
    }
  }
}
