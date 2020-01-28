//
//  ViewController.swift
//  RealTimeFaceTracking
//
//  Created by しゅん on 2020/01/18.
//  Copyright © 2020 g-chan. All rights reserved.
//

import UIKit

class ViewController: UIViewController {

    var faceTracker:FaceTracker? = nil;
    @IBOutlet weak var cameraView: UIView!
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view.
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        faceTracker = FaceTracker(view: self.cameraView, findface:{arr in
            
        })
    }
}

