//
//  PostDetailView.swift
//  final_project
//
//  Created by liblabs-mac on 3/2/19.
//  Copyright © 2019 liblabs-mac. All rights reserved.
//

import UIKit
import Firebase
import FirebaseDatabase

class PostDetailView : UIViewController, UITableViewDelegate, UITableViewDataSource {
    @IBOutlet weak var groupTitleLabel: UILabel!
    @IBOutlet weak var messageContentLabel: UILabel!
    @IBOutlet weak var tableView: UITableView!
    @IBOutlet weak var navBar: UINavigationItem!
    
    var post: TextPost?
    var groupName: String?
    
    var commentList = [TextPost]()
    
    var databaseRef : DatabaseReference!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 64
        
        groupTitleLabel.text = "Group:\n" + (groupName ?? "N/A")
        messageContentLabel.text = "Message:\n" +  (post?.content ?? "N/A")
        
        let backButton: UIBarButtonItem = UIBarButtonItem(title: "< Back", style: UIBarButtonItem.Style.plain, target: self, action: #selector(backPressed(_:)))
        
        navBar.backBarButtonItem = backButton
        navBar.leftBarButtonItem = backButton
        
        databaseRef = Database.database().reference().child("Groups")
            .child(groupName ?? "Cal Poly").child("posts").child(post!.dateCreated).child("comments")
        
        retrieveComments()
    }
    
    func retrieveComments() {
        databaseRef?.queryOrdered(byChild: "comments")
            .observe(.value, with:
                { snapshot in
                    
                    self.commentList = []
                    
                    for item in snapshot.children {
                        let actItem = item as! DataSnapshot
                        self.commentList.append(TextPost(snapshot: actItem))
                    }
                    
                    self.tableView.reloadData()
            })
    }
    
    @IBAction func addCommentPressed(_ sender: Any) {
        performSegue(withIdentifier: "addComment", sender: self)
    }
    
    @IBAction func backPressed(_ sender: Any) {
        performSegue(withIdentifier: "unwindToPosts", sender: self)
    }
    
    func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return commentList.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "commentCell", for: indexPath) as? CommentCell
        
        let comment = commentList[indexPath.row]
        cell?.commentLabel.text = comment.content
        
        return cell!
    }
    
    @IBAction func unwindToPostDetail(segue: UIStoryboardSegue) {
        retrieveComments()
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if segue.identifier == "addComment" {
            let destVC = segue.destination as? AddCommentViewController
            destVC?.groupTitle = groupName ?? "Cal Poly"
            destVC?.postToCommentOn = post!
            destVC?.header = "Comment on: " + (groupName ?? "Cal Poly")
        }
    }
}