//
//  Passwordstore.swift
//  passafari
//
//  Created by Artur Sterz on 28.10.18.
//  Copyright © 2018 Artur Sterz. All rights reserved.
//

import Foundation

import ObjectivePGP

class Passwordstore {
    var fuzzySearchScore: Double
    var passwordStoreUrl: URL
    var pgpKeyRing: Keyring = Keyring()
    
    init(score fuzzySearchScore: Double, url passwordStoreUrl: URL){
        self.fuzzySearchScore = fuzzySearchScore
        self.passwordStoreUrl = passwordStoreUrl
    }
    
    func passSearch(password: String) -> [String] {
        var resultPaths = [String]()
        
        if self.passwordStoreUrl.startAccessingSecurityScopedResource() {
            let fileSystem = FileManager.default
            if let fsTree = fileSystem.enumerator(atPath: self.passwordStoreUrl.path) {
                // Iterate over all files and folders in the default store path. Several checks will be done.
                while let fsNodeName = fsTree.nextObject() as? String {
                    let fullPath = "\(String(describing: self.passwordStoreUrl))\(fsNodeName)"
                    var pathComponents = URL(fileURLWithPath: fullPath).pathComponents
                    
                    // To not accidentally exclude a valid encrypted file from the search path, we remove it beforehand from the .git search components.
                    if pathComponents.last!.hasSuffix(".gpg") {
                        pathComponents.removeLast()
                    } else {
                        continue
                    }
                    
                    // If a password store is a git folder, we do not want to iterate over the entire repository, but only the current working copy.
                    // Therefore, we need to exclude all folders containing .git from the search items.
                    if pathComponents.contains(where:
                        { (pathComponent) -> Bool in
                            return pathComponent.contains(".git")
                    }) {
                        continue
                    }
                    
                    // The final scoring. If a path matches at least FUZZY_SEARCH_SCORE, we remember it.
                    if FuzzySearch.score(originalString:fullPath, stringToMatch: password) > self.fuzzySearchScore {
                        resultPaths.append(fsNodeName)
                    }
                }
            }
        }
        
        self.passwordStoreUrl.stopAccessingSecurityScopedResource()
        
        return resultPaths
    }
    
    func passDecrypt(pathToFile: String) -> String {
        var resultPassword = ""
        if self.passwordStoreUrl.startAccessingSecurityScopedResource() {
            do {
                let encryptedFileUrl = passwordstore!.passwordStoreUrl.appendingPathComponent(pathToFile)
                let encryptedFile = try Data(contentsOf: encryptedFileUrl)
                
                let decryptedPassword = try ObjectivePGP.decrypt(encryptedFile, andVerifySignature: false, using: self.pgpKeyRing.keys, passphraseForKey: { (key) -> String? in
                    return "supersecretpassphrase"
                })
                
                resultPassword = String(data: decryptedPassword, encoding: .utf8) ?? ""
            } catch {
                return ""
            }
            
            self.passwordStoreUrl.stopAccessingSecurityScopedResource()
        }
        
        return resultPassword
    }
    
    func importKeys(keyFilePath: String) throws {
        self.pgpKeyRing.import(keys: try! ObjectivePGP.readKeys(fromPath: keyFilePath))
    }
}