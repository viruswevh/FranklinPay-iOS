//
//  WalletViewController.swift
//  DiveLane
//
//  Created by Anton Grigorev on 08/09/2018.
//  Copyright © 2018 Matter Inc. All rights reserved.
//

import UIKit

class WalletViewController: UIViewController {

    @IBOutlet weak var walletTableView: UITableView!
    @IBOutlet weak var blockchainControl: UISegmentedControl!

    let conversionService = FiatServiceImplementation.service

    var localDatabase: ILocalDatabase?
    var keysService: IKeysService?
    var wallets: [KeyWalletModel]?
    var twoDimensionalTokensArray: [ExpandableTableTokens] = []

    let animation = AnimationController()

    let design = DesignElements()

    lazy var refreshControl: UIRefreshControl = {
        let refreshControl = UIRefreshControl()
        refreshControl.addTarget(self, action:
        #selector(self.handleRefresh(_:)),
                for: UIControl.Event.valueChanged)
        refreshControl.tintColor = UIColor.blue

        return refreshControl
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        animation.waitAnimation(isEnabled: true, notificationText: "Loading initial data", on: self.view)
        self.tabBarController?.tabBar.selectedItem?.title = nil
        let nib = UINib.init(nibName: "TokenCell", bundle: nil)
        self.walletTableView.delegate = self
        self.walletTableView.dataSource = self
        self.walletTableView.tableFooterView = UIView()
        self.walletTableView.addSubview(self.refreshControl)
        self.walletTableView.register(nib, forCellReuseIdentifier: "TokenCell")
        self.navigationItem.setRightBarButton(settingsWalletBarItem(), animated: false)
    }

    func initDatabase(complection: @escaping () -> Void) {
        localDatabase = LocalDatabase()
        wallets = localDatabase?.getAllWallets()
        keysService = KeysService()
        complection()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        self.title = "Wallets"
        self.tabBarController?.tabBar.selectedItem?.title = nil

    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        updateTable()
    }

    func unselectAll() {
        var indexPath = IndexPath(row: 0, section: 0)
        for wallet in twoDimensionalTokensArray {
            for _ in wallet.tokens {
                self.twoDimensionalTokensArray[indexPath.section].tokens[indexPath.row].isSelected = false
                walletTableView.cellForRow(at: indexPath)?.accessoryView?.tintColor = .lightGray
                indexPath.row += 1
            }
            indexPath.section += 1
            indexPath.row = 0
        }
    }

    func selectToken(cell: UITableViewCell) {

        unselectAll()

        guard let indexPathTapped = walletTableView.indexPath(for: cell) else {
            return
        }

        let token = twoDimensionalTokensArray[indexPathTapped.section].tokens[indexPathTapped.row]
        print(token)

        CurrentToken.currentToken = token.token

        localDatabase?.selectWallet(wallet: token.inWallet, completion: { [weak self] in
            self?.twoDimensionalTokensArray[indexPathTapped.section].tokens[indexPathTapped.row].isSelected = true
            cell.accessoryView?.tintColor = Colors.NavBarColors.mainTint
        })
    }

    @objc func handleRefresh(_ refreshControl: UIRefreshControl) {
        updateTable()
    }

    func updateTable() {
        twoDimensionalTokensArray.removeAll()
        switch blockchainControl.selectedSegmentIndex {
        case 0:
            updateEtherBlockchain()
        default:
            updatePlasmaBlockchain()
        }
    }

    func settingsWalletBarItem() -> UIBarButtonItem {
        let addButton = UIBarButtonItem(image: UIImage(named: "settings_blue"),
                                        style: .plain,
                                        target: self,
                                        action: #selector(settingsWallet))
        return addButton
    }

    @objc func settingsWallet() {
        let walletsViewController = WalletsViewController()
        self.navigationController?.pushViewController(walletsViewController, animated: true)
    }

    @IBAction func addWallet(_ sender: UIButton) {
        let addWalletViewController = AddWalletViewController(isNavigationBarNeeded: true)
        self.navigationController?.pushViewController(addWalletViewController, animated: true)
    }

    func getTokensListForEtherBlockchain(completion: @escaping () -> Void) {
        guard let wallets = wallets else {
            return
        }

        let networkID = CurrentNetwork().getNetworkID()

        for wallet in wallets {
            let tokensForWallet = localDatabase?.getAllTokens(for: wallet, forNetwork: networkID)
            let isSelectedWallet = wallet == keysService?.selectedWallet() ? true : false
            if let tokens = tokensForWallet {

                let expandableTokens = ExpandableTableTokens(isExpanded: true,
                        tokens: tokens.map {
                            TableToken(token: $0,
                                    inWallet: wallet,
                                    isSelected: ($0 == CurrentToken.currentToken) && isSelectedWallet)
                        })
                twoDimensionalTokensArray.append(expandableTokens)
                completion()
            }
        }
    }

    func updatePlasmaBlockchain() {
        guard let wallets = wallets else {
            return
        }
        for wallet in wallets {
            let plasmaToken = ERC20TokenModel(name: "Matter Plasma Ether", address: "", decimals: "18", symbol: "ETH")
            let tokens = [plasmaToken]
            let expandableTokens = ExpandableTableTokens(isExpanded: true,
                                                         tokens: tokens.map {
                                                            TableToken(token: $0,
                                                                       inWallet: wallet,
                                                                       isSelected: ($0.name == plasmaToken.name))
            })
            twoDimensionalTokensArray.append(expandableTokens)
            refreshControl.endRefreshing()
            walletTableView.reloadData()
        }
    }

    func updateEtherBlockchain() {
        initDatabase { [weak self] in
            self?.twoDimensionalTokensArray.removeAll()
            self?.getTokensListForEtherBlockchain { [weak self] in
                DispatchQueue.main.async {
                    self?.refreshControl.endRefreshing()
                    self?.walletTableView.reloadData()
                    self?.animation.waitAnimation(isEnabled: false, notificationText: "Loading initial data", on: (self?.view)!)
                }
            }
        }
    }

    @IBAction func blockchainChanged(_ sender: UISegmentedControl) {
        updateTable()
    }

}

extension WalletViewController: UITableViewDelegate, UITableViewDataSource {

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let backgroundView = design.tableViewHeaderBackground(in: self.view)

        let walletButton = design.tableViewHeaderWalletButton(in: self.view,
                withTitle: "Wallet \(twoDimensionalTokensArray[section].tokens.first?.inWallet.name ?? "")",
                withTag: section)
        walletButton.addTarget(self, action: #selector(handleExpandClose), for: .touchUpInside)
        backgroundView.addSubview(walletButton)

        let addButton = design.tableViewAddTokenButton(in: self.view, withTag: section)
        addButton.addTarget(self, action: #selector(handleAddToken), for: .touchUpInside)
        backgroundView.addSubview(addButton)

        return backgroundView
    }

    @objc func handleExpandClose(button: UIButton) {

        let section = button.tag

        var indexPaths = [IndexPath]()
        for row in twoDimensionalTokensArray[section].tokens.indices {
            let indexPath = IndexPath(row: row, section: section)
            indexPaths.append(indexPath)
        }

        let isExpanded = twoDimensionalTokensArray[section].isExpanded
        twoDimensionalTokensArray[section].isExpanded = !isExpanded

        if isExpanded {
            walletTableView.deleteRows(at: indexPaths, with: .fade)
        } else {
            walletTableView.insertRows(at: indexPaths, with: .fade)
        }
    }

    @objc func handleAddToken(button: UIButton) {

        let section = button.tag

        let wallet = twoDimensionalTokensArray[section].tokens.first?.inWallet

        let searchTokenController = SearchTokenViewController(for: wallet)
        self.navigationController?.pushViewController(searchTokenController, animated: true)

    }

    func numberOfSections(in tableView: UITableView) -> Int {
        return twoDimensionalTokensArray.count
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 80
    }

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        return 45
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if !twoDimensionalTokensArray[section].isExpanded {
            return 0
        }

        return twoDimensionalTokensArray[section].tokens.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(withIdentifier: "TokenCell",
                                                       for: indexPath) as? TokenCell else {
            return UITableViewCell()
        }
        cell.link = self
        let token = twoDimensionalTokensArray[indexPath.section].tokens[indexPath.row]
        cell.configure(token: token.token,
                       forWallet: token.inWallet)

        cell.accessoryView?.tintColor = Colors.ButtonColors().changeSelectionColor(dependingOnChoise: token.isSelected)

        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {

        guard let indexPathForSelectedRow = tableView.indexPathForSelectedRow else {
            return
        }
        let cell = tableView.cellForRow(at: indexPathForSelectedRow) as? TokenCell

        guard let selectedCell = cell else {
            return
        }

        guard let indexPathTapped = walletTableView.indexPath(for: selectedCell) else {
            return
        }

        let token = twoDimensionalTokensArray[indexPathTapped.section].tokens[indexPathTapped.row]

        let tokenViewController = TokenViewController(
                wallet: token.inWallet,
                token: token.token,
                tokenBalance: selectedCell.balance.text ?? "0")
        self.navigationController?.pushViewController(tokenViewController, animated: true)
        tableView.deselectRow(at: indexPath, animated: true)

    }

    func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        if twoDimensionalTokensArray[indexPath.section].tokens[indexPath.row].token == ERC20TokenModel(isEther: true) {
            return
        }
        if editingStyle == .delete {
            let networkID = CurrentNetwork().getNetworkID()
            localDatabase?.deleteToken(
                token: twoDimensionalTokensArray[indexPath.section].tokens[indexPath.row].token,
                forWallet: twoDimensionalTokensArray[indexPath.section].tokens[indexPath.row].inWallet,
                forNetwork: networkID,
                completion: { [weak self] (error) in
                if error == nil {
                    self?.updateTable()
                }
            })
        }
    }

}
