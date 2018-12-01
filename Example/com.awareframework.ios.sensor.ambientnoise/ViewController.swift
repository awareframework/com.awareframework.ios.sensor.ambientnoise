//
//  ViewController.swift
//  com.awareframework.ios.sensor.ambientnoise
//
//  Created by tetujin on 11/19/2018.
//  Copyright (c) 2018 tetujin. All rights reserved.
//

import UIKit

import com_awareframework_ios_sensor_ambientnoise

class ViewController: UIViewController {
    var sensor: AmbientNoiseSensor? = nil
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
        
//        sensor = AmbientNoiseSensor.init(AmbientNoiseSensor.Config().apply{ config in
//            config.debug = true
//        })
//        sensor?.start()
        
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }

}

