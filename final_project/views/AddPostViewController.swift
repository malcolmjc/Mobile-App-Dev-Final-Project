//
//  AddPostViewController.swift
//  final_project
//
//  Created by liblabs-mac on 3/2/19.
//  Copyright © 2019 liblabs-mac. All rights reserved.
//

import UIKit
import FirebaseDatabase
import Firebase

class AddPostViewController: UIViewController, UITextViewDelegate {
    var header: String!
    var groupName: String?
    
    @IBOutlet weak var groupTitleLabel: UILabel!
    @IBOutlet weak var textView: UITextView!
    
    var databaseRef : DatabaseReference!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        databaseRef = Database.database().reference().child("Groups").child(groupName ?? "Cal Poly")
        
        groupTitleLabel.text = header
        textView.delegate = self
        textView.text = "Message goes here..."
        textView.textColor = UIColor.lightGray
    }
    
    func textViewDidBeginEditing(_ textView: UITextView) {
        if textView.textColor == UIColor.lightGray {
            textView.text = nil
            textView.textColor = UIColor.black
        }
    }
    
    func textViewDidEndEditing(_ textView: UITextView) {
        if textView.text.isEmpty {
            textView.text = "Message goes here..."
            textView.textColor = UIColor.lightGray
        }
    }
    
    var newPost: TextPost?
    
    var cancelled = false
    @IBAction func submitPressed(_ sender: Any) {
        if (!textView.text!.isEmpty) {
            newPost = TextPost(textView.text)
            let newPostRef = databaseRef.child("posts").child(newPost!.dateCreated)
            newPostRef.setValue(newPost?.toAnyObject())
            performSegue(withIdentifier: "unwindToPosts", sender: self)
        }
    }
    
    @IBAction func cancelPressed(_ sender: Any) {
        cancelled = true
        performSegue(withIdentifier: "unwindToPosts", sender: self)
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if segue.identifier == "unwindToPosts" {
            let destVC = segue.destination as? FirstViewController
            if (!cancelled) {
                destVC?.messageList.append(newPost!)
            }
        }
    }
}

