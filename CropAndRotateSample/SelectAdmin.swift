//
//  SelectAdmin.swift
//  SBQ_Editing_Screens
//
//  Created by Rajat Bhatt on 01/08/17.
//  Copyright © 2017 Rajat Bhatt. All rights reserved.
//

import UIKit

protocol RemoveAdminSelectPopup {
    func adminSelectPopupRemoved()
}

class SelectAdmin: UIViewController {

    @IBOutlet weak var viewAllAdminButton: UIButton!
    @IBOutlet weak var adminTableVIewOutlet: UITableView!
    
    var selectedCell: SelectAdminTableViewCell?
    var removeAdminSelectPopup: RemoveAdminSelectPopup?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        showAnimate()
        viewAllAdminButton.layer.borderWidth = 2
        viewAllAdminButton.layer.borderColor = #colorLiteral(red: 0.2418460846, green: 0.7380391955, blue: 0.7409901023, alpha: 1).cgColor
        viewAllAdminButton.layer.masksToBounds = true
        viewAllAdminButton.layer.cornerRadius = viewAllAdminButton.frame.size.height/2
        
        adminTableVIewOutlet.register(UINib(nibName: "SelectAdminTableViewCell", bundle: nil), forCellReuseIdentifier: "cell")
    }
    
    @IBAction func BackgroundButtonClicked(_ sender: UIButton) {
        removeAnimate()
        removeAdminSelectPopup?.adminSelectPopupRemoved()
    }
    
    func showAnimate()
    {
        self.view.transform = CGAffineTransform(scaleX: 1.3, y: 1.3)
        self.view.alpha = 0.0
        UIView.animate(withDuration: 0.25, animations: {
            self.view.alpha = 1.0
            self.view.transform = CGAffineTransform(scaleX: 1.0, y: 1.0)
        })
    }
    
    func removeAnimate()
    {
        UIView.animate(withDuration: 0.25, animations: {
            self.view.transform = CGAffineTransform(scaleX: 1.3, y: 1.3)
            self.view.alpha = 0.0
        }, completion: {(finished : Bool) in
            if(finished)
            {
                self.willMove(toParentViewController: nil)
                self.view.removeFromSuperview()
                self.removeFromParentViewController()
            }
        })
    }
}
extension SelectAdmin: UITableViewDelegate, UITableViewDataSource {
    func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return 5
    }
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cellIdentifier = "cell"
        let cell = adminTableVIewOutlet.dequeueReusableCell(withIdentifier: cellIdentifier) as! SelectAdminTableViewCell
        cell.nameLabel.text = "Administrator \(indexPath.row+1)"
        return cell
    }
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let cell = adminTableVIewOutlet.cellForRow(at: indexPath) as! SelectAdminTableViewCell
        cell.selectedButton.isSelected = !cell.selectedButton.isSelected
        if self.selectedCell != nil {
            self.selectedCell?.selectedButton.isSelected = !(self.selectedCell?.selectedButton.isSelected)!
            self.selectedCell = cell
        } else {
            self.selectedCell = cell
        }
    }
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 61
    }
}
