//
//  SelectAdminTableViewCell.swift
//  SBQ_Editing_Screens
//
//  Created by Rajat Bhatt on 01/08/17.
//  Copyright © 2017 Rajat Bhatt. All rights reserved.
//

import UIKit

class SelectAdminTableViewCell: UITableViewCell {

    @IBOutlet weak var nameLabel: UILabel!
    @IBOutlet weak var selectedButton: UIButton!
    override func awakeFromNib() {
        super.awakeFromNib()
        // Initialization code
    }

    override func setSelected(_ selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)

        // Configure the view for the selected state
    }
    
}
