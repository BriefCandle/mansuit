// SPDX-License-Identifier: MIT LICENSE

pragma solidity ^0.8.0;

import "./IERC721Receiver.sol";
// import "./Pausable.sol";
import "./ManSuit.sol";
import "./PASTE.sol";

/**
 * @dev Brief Explanation
 * 
 * There are four sections in Area, conceptually speaking. Each is organized with one 
 * mapping along with one array for easy access. Two sections will earn players PASTE 
 * staking award: ie., stakedHuman & stakedManSuit. The other two will serve other 
 * functionalities: i.e., duels & limbo; 
 *
 * Some gaming mechanisms are worth mentioning. First, infection(), a passive ability 
 * poccessed by mansuits. In particular, mansuits staked (stored in "stakedManSuit") are 
 * capable of accumulating cumInfectionPower. Anyone in public is able to invoke 
 * infection() to try to infect any human staked (stored in "stakedHuman").
 *
 * Second, termination(), an active ability poccessed by humans. In particular, any 
 * human staked are capable of initiating a termination process to eliminate a (psudo-) 
 * randomly selected mansuit staked. 
 *
 * Lastly, limbo, a safe place within the Area, is created to prevent any particular 
 * human from being targeted and being too easily reduced into meatpie. It does provide 
 * human owners with options, which comes with a certain cost to hedge uncertain future 
 * risk. So, it is fair.
 */

contract Area is Ownable, IERC721Receiver {

    struct Stake {
        uint16 tokenId;
        uint80 value;
        address owner;
        bool escape;
    }

    struct PasteShare {
        uint256 shareAmount; // in $PASTE
        uint80 infectedTime;
    }

    struct Duel {
        uint256 humanId;
        address humanOwner;
        bool escape;
        uint256 manSuitId;
        address manSuitOwner;
        uint256 commitNumber; 
    }

    // events for stake & claim
    event StakeHuman(address owner, uint256 tokenId, uint256 value, bool isEscape);
    event StakeManSuit(address owner, uint256 tokenId, uint256 value);
    event ClaimHuman(uint256 tokenId, uint256 earned, bool unstake);
    event ClaimManSuit(uint256 tokenId, uint256 earned, bool unstake);
    event UpdateEarning(uint256 total);
    // event for infection
    event InfectionTriggered(uint256 timestamp);
    event HumanInfected(uint256 tokenId);
    event UpdateInfectionPower(uint256 power);
    // events for limbo
    event ChooseFromLimbo(uint256 tokenId, bool unstake);
    // event for unclaimed
    event claimUnclaimed(address claimer, uint256 amount);
    // event for termination
    event InitTermination(uint256 humanId, uint256 manSuitId);
    event CompleteTermination(uint256 humanId, uint256 manSuitId, bool success);

    // reference to the mansuit NFT contract; initialized in onlyOwner function
    ManSuit manSuit;
    // reference to the $PASTE contract for minting $PASTE earnings;
    PASTE paste;

    // maps human tokenId to stake in area
    mapping(uint256 => Stake) public stakedHuman;
    // array of staked human tokenId - for the purpose of infection
    uint256[] public stakedHumanIds;
    // maps human tokenId to stake in area
    mapping(uint256 => Stake) public stakedManSuit;
    // array of staked mansuit tokenId - for the purpose of termination
    uint256[] public stakedManSuitIds;
    // array that contains paste share for each mansuit staked before infection
    PasteShare[] public pasteShares;
    // maps mansuit tokenId to stake in limbo
    mapping(uint256 => Stake) public limboManSuit;
    // array of mansuit in limbo - for the purpose of infection + termination
    uint256[] public limboList;
    // maps human tokenId to duel in duels
    mapping(uint256 => Duel) public duels;
    // array of duel info - for the purpose of duel
    uint256[] public duelList;
    // maps address to unclaimed $PASTE
    mapping(address => uint256) public unclaimedPaste;


    // max amount of human be infected by one mansuit, per day
    uint256 public constant DAILY_INFECTION_RATE = 1; 
    // amount of PASTE extracted from one human
    uint256 public constant PASTE_PER_HUMAN = 1 ether;
    // amount of PASTE awarded to staking NFT
    uint256 public constant DAILY_PASTE_RATE = 1 ether;
    // escape ready human must take a 20% tax cut
    uint256 public constant PASTE_ESCAPE_AFTER_TAX = 80;
    // minimum duration before unstake without paying tax 
    uint256 public constant MINIMUM_TO_EXIT = 2 days;
    // tax for paying early-unstaking
    uint256 public constant PASTE_CLAIM_AFTER_TAX = 80;
    // max amount of $PASTE available through staking in this area
    uint256 public constant MAXIMUM_AREA_PASTE = 120000 ether;
    // minimum duration for infection() to be called: 2 hours
    uint256 public constant MINIMUM_INFECTION_INTERVAL = 7200;
    // amount of PASTE to be rewarded for an infection() call
    uint256 public constant PASTE_AWARD_INFECTION = 0.2 ether;
    // cost of PASTE to restore from mansuit to human
    uint256 public RESTORATION_COST = 1.5 ether;
    // cost of PASTE for human to terminate a mansuit
    uint256 public TERMINATION_COST = 0.5 ether;


    // amount of $PASTE earned so far
    uint256 public totalPasteEarned;
    // the last time $PASTE was claimed
    uint256 public lastClaimTimestamp;

    // amount of infection ever occured in this area
    uint256 public totalInfected;
    // last time infection() is being called
    uint256 public lastInfectTimestamp;
    // cumulative infection power, updated at lastManSuitChanged
    uint256 public cumInfectionPower;
    // last time staked mansuit is changed
    uint256 public lastManSuitChanged;
    // the distribution table used to compute infection probability; weight range from [0-3]; 
    // later, can use alias method for accuracy
    uint16[] public weightDistribution = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9];

    constructor(address _paste) {
        paste = PASTE(_paste);
    }

     /** ---- ADMIN ---- */
    function setManSuit(address _manSuit) external onlyOwner {
        manSuit = ManSuit(_manSuit);
    }

    /** ---- STAKE ---- */
    
    /**
     * @dev transfer human and mansuit ownership to Area so that registered owners are allowed 
     * (pursuant to code law) to make changes to states and uri of other nfts staked in Area
     * @param account: staker's address
     * @param tokenIds: human and mansuit IDs to stake
     * @param escape: = true allows human to hide in limbo if infected
     */
    function stakeManyToArea(address account, uint16[] calldata tokenIds, bool escape) external _updateEarnings {
        require(account == _msgSender(), "only by account");
        for (uint i = 0; i < tokenIds.length; i++) {
            require(manSuit.ownerOf(tokenIds[i]) == _msgSender(), "only owner");
            manSuit.transferFrom(_msgSender(), address(this), tokenIds[i]);
            if (isHuman(tokenIds[i])) _moveHumanToArea(account, tokenIds[i], escape);
            else if (isManSuit(tokenIds[i])) _moveManSuitToArea(account, tokenIds[i]);
            // if isMeatPie, it will be transferred to area with no hope of getting back
        }
    }

    /**
     * @dev state change: add human info into stakedHuman mapping, human Id in stakedHumanIds array
     * NOTE modifier check whether the current staked human is zero; if yes, then invoke resume infection
     */
    function _moveHumanToArea(address account, uint256 tokenId, bool escape) private _firstHumanCheck {
        uint80 value = uint80(block.timestamp);
        stakedHuman[tokenId] = Stake({
            owner: account,
            tokenId: uint16(tokenId),
            value: value,
            escape: escape
        });
        stakedHumanIds.push(tokenId); 

        emit StakeHuman(_msgSender(), tokenId, value, escape);
    }

    /**
     * @dev state change: add mansuit info into stakedManSuit mapping, stakedManSuitIds in stakedHumanIds array
     * NOTE infection power is updated whenever man-suit staked is about to change
     */
    function _moveManSuitToArea(address account, uint256 tokenId) private  {
        _updateInfectionPower();
        uint80 value = uint80(block.timestamp);
        stakedManSuit[tokenId] = Stake({
            owner: account,
            tokenId: uint16(tokenId),
            value: value,
            escape: false
        });
        stakedManSuitIds.push(tokenId);

        emit StakeManSuit(_msgSender(), tokenId, value);
    }


    /** ---- CLAIM ---- */
    /**
     * @dev claim (to earn PASTE) or claim & unstake (to regain ownership) humans & mansuits from Area
     * @param tokenIds: an array containing the tokenIds the player previously owned
     * @param unstake: true to unstake, false to just claim
     * NOTE infection() is invoked before the control of nfts are about to change (ie., unstake)
     */
    function claimManyFromArea(uint16[] calldata tokenIds, bool unstake) external _updateEarnings {
        uint256 owed;
        if (unstake) infection();
        for (uint i = 0; i < tokenIds.length; i++) {
            if (isHuman(tokenIds[i])) 
                owed += _claimHumanFromArea(tokenIds[i], unstake);
            else if (isManSuit(tokenIds[i]))
                owed += _claimManSuitFromArea(tokenIds[i], unstake);
        }
        if (owed == 0) return;
        paste.mint(_msgSender(), owed);   
    }

    /**
     * @dev either 1) claim PASTE base award based on value after resetting huamn's value; or
     * 2) unstake human: rather than resetting, clean up human staked info; then transfer back ownership
     * return owed: PASTE owed to be minted in the last of the process.
     */
    function _claimHumanFromArea(uint256 tokenId, bool unstake) private returns (uint256 owed) { 
        Stake memory stake = stakedHuman[tokenId]; 
        require(stake.owner == _msgSender(), "only owner");
        owed = _calculateBaseAward(stake.value, stake.escape);
        if (unstake) {
            _removeHumanFromArea(tokenId);
            manSuit.safeTransferFrom(address(this), _msgSender(), tokenId, ""); 
        } else { // reset stake's value
            stakedHuman[tokenId] = Stake({
                owner: _msgSender(),
                tokenId: uint16(tokenId),
                value: uint80(block.timestamp),
                escape: stake.escape
            }); 
        }
        emit ClaimHuman(tokenId, owed, unstake);
    }

    /**
     * @dev state change: delete human info in stakedHuman, human id in stakedHumanIds
     */
    function _removeHumanFromArea(uint256 tokenId) private {
        delete stakedHuman[tokenId];
        _arrayRemoveValue(tokenId, stakedHumanIds);
    }

    /**
     * @dev either 1) claim mansuit's base + infection bonus award based on value & pasteshares; or
     * 2) unstake mansuit: rather than resetting, clean up mansuit staked info, and then transfer back ownership
     */
    function _claimManSuitFromArea(uint256 tokenId, bool unstake) private returns (uint256 owed) { 
        Stake memory stake = stakedManSuit[tokenId]; 
        require(stake.owner == _msgSender(), "only owner");
        owed = _calculateBaseAward(stake.value, false);
        owed += _calculateInfectionBonus(tokenId);
        if (unstake) {
            _removeManSuitFromArea(tokenId);
            manSuit.safeTransferFrom(address(this), _msgSender(), tokenId, ""); 
        } else { // reset stake
            stakedManSuit[tokenId] = Stake({
                owner: _msgSender(),
                tokenId: uint16(tokenId),
                value: uint80(block.timestamp),
                escape: false
            }); 
        }
        emit ClaimManSuit(tokenId, owed, unstake);
    }

    /**
     * @dev state change: delete mansuit info in stakedManSuit, mansuit id in stakedManSuitIds
     * NOTE: infection power is updated when staked mansuit is about to change
     */
    function _removeManSuitFromArea(uint256 tokenId) private {
        _updateInfectionPower();
        delete stakedManSuit[tokenId];
        _arrayRemoveValue(tokenId, stakedManSuitIds);
    }

    /**
     * @dev calculate base award for human and mansuits when they are about to be removed from staking: 
     * i.e., claim(), moveToLimbo(), moveToDuel()
     * NOTE: totalPasteEarned & lastClaimTimestamp is tracked to keep total paste award from exceeding MAX:
     * 1) no award if staked after lastClaimTimestamp
     * 2) stop awarding additional $PASTE after lastClaimTimestamp
     */
    function _calculateBaseAward(uint80 value, bool escape) private view returns (uint256 award) {
        if (totalPasteEarned < MAXIMUM_AREA_PASTE) {
            award = (block.timestamp - value) * DAILY_PASTE_RATE / 1 days;
        } else if (value > lastClaimTimestamp) { 
            award = 0; 
        } else { 
            award = (lastClaimTimestamp - value) * DAILY_PASTE_RATE / 1 days; 
        }
        if ((block.timestamp - value) < MINIMUM_TO_EXIT) {
            award = award * PASTE_CLAIM_AFTER_TAX / 100;
        }
        uint256 escapeAfterTax = escape ? PASTE_ESCAPE_AFTER_TAX : 100;
        award = award * escapeAfterTax / 100;
    }

    /**
     * @dev update totalPasteEarned & lastClaimTimestamp whenever staked human  & mansuit are about to change: 
     * i.e., move in or out from staked area. 
     * ---------------- CHANGE --------------- 
     * NOTE PASTE award deducted due to tax is included in totalPasteEarned, meaning that the actual
     * total PASTE received will be less than MAXIMUM_AREA_PASTE
     */
    modifier _updateEarnings() {
        if (totalPasteEarned < MAXIMUM_AREA_PASTE) {
            totalPasteEarned += (block.timestamp - lastClaimTimestamp)
            * (stakedHumanIds.length + stakedManSuitIds.length) * DAILY_PASTE_RATE / 1 days; 
            lastClaimTimestamp = block.timestamp;
        }
        _;
    }



    /** --- INFECTION --- */
    /** 
     * @dev infection() is tried before any unstake happens; it can also be called by anyone; 
     * TODO ------------ shall we worry about front-run? -------------
     * a successful call will award caller PASTE
     * modifier: infectionCheck; if passes, the rest will run:
     * 1) infection power is updated, on which 2) new infected amount can be calculated
     * 3) randomly select humans, call infectHuman on them, 4) update pasteShares which 
     * is used to calculate infection bonus PASTE for mansuits
     */
    function infection() public infectionCheck {  
        _updateInfectionPower(); // 1) 
        uint256 amount = calculateInfectedAmount(); // 2) 
        amount = amount > stakedHumanIds.length ? stakedHumanIds.length : amount; 
        if (amount > 0) {
            for (uint i = 0; i < amount; i++) { // 3)
                uint256 index = _randomIndexFromArray(i, stakedHumanIds);
                uint256 humanId = stakedHumanIds[index]; 
                _infectHuman(humanId);
            }
            totalInfected += amount;
            pasteShares.push(PasteShare({ // 4)
                shareAmount: amount * PASTE_PER_HUMAN / stakedManSuitIds.length, // what if stakedManSuitIds.length = 0??
                infectedTime: uint80(block.timestamp)
            }));
        }
  
        paste.mint(_msgSender(), PASTE_AWARD_INFECTION);
    }

    /**
     * @dev check on whether infection should be invoked. Two conditions: 
     * 1) time elipsed must be longer than an INTERVAL, and 
     * 2) stakedHumanIds && stakedManSuitIds must not be empty
     */
    modifier infectionCheck() {
        if ((block.timestamp - lastInfectTimestamp) >= MINIMUM_INFECTION_INTERVAL && 
        stakedHumanIds.length != 0 && stakedManSuitIds.length != 0)  { 
            lastInfectTimestamp = block.timestamp;
            emit InfectionTriggered(block.timestamp);
            _;
        }
    }


    /** 
     * @dev called to update cumInfectionPower & lastManSuitChanged, which is an anchor 
     * point to increment infection Power. It is called 1) BEFORE staked mansuit is 
     * about to change (move in or move out), 2) BEFORE calculateInfectionAmount() is invoked
     */
    function _updateInfectionPower() private { 
        if (stakedHumanIds.length > 0) {       
            uint256 change = (block.timestamp - lastManSuitChanged) * stakedManSuitIds.length;
            if (change > 0) {
                cumInfectionPower += change;
                lastManSuitChanged = block.timestamp;
                emit UpdateInfectionPower(cumInfectionPower);
            }
        }
    }

    /**
     * calculate the amount of human shall be infected based on the current cumInfectionPower
     */
    function calculateInfectedAmount() public view returns (uint256 amount) { 
        uint256 randomN = (random(cumInfectionPower) & 0xFFFFFFFF) % weightDistribution.length; 
        // calculate weight based on distribution table & a pseudo random number
        uint8 weight;
        if (randomN < 2) weight = 0;
        else if (randomN > 7) weight = 2;
        else weight = 1;
        weight = 2; // ---******** delete it!!!!!! ****** ------
        amount = weight * cumInfectionPower * DAILY_INFECTION_RATE / 2 / 1 days; // put "/2" because the max weight is 2
        amount = amount <= totalInfected ? 0 : amount - totalInfected;
        return amount;
    }

    /** 
     * @dev four state changes happen in sequence here:
     * 1) human info is removed from staked; 2) human is transformed to mansuit; 3) any unclaimed PASTE is saved
     * 4) move human info (now mansuit) to limbo (if escape) or back to staked (if ~escape), both of which will 
     * reset its stake value
     * @param tokenId: the humanId to be infected
     */
    // pass in the index and id of stakedHumanIds to make it infected
    function _infectHuman(uint256 tokenId) private {
        Stake memory stake = stakedHuman[tokenId];
        _removeHumanFromArea(tokenId); // 1) 
        manSuit.transformToManSuit(tokenId); // 2) 
        unclaimedPaste[stake.owner] += _calculateBaseAward(stake.value, stake.escape); // 3)
        if (stake.escape) _moveManSuitToLimbo(stake); // 4)
        else _moveManSuitToArea(stake.owner, tokenId);
        
        emit HumanInfected(tokenId);
    }

    /**
     * @dev unclaimed PASTEs will be saved in four situation: 
     * 1) base award for human when it is infected and moves to limbo, claimable to human owner
     * 2) base award for human when it enters initTermination, claimable to human owner
     * 3) base + bonus award for mansuit when it enters initTermination, claimable to mansuit owner
     * 4) termination award for mansuit when it wins termination, claimable to mansuit owner
     */
    function claimUnclaimedPaste(address account) public {
        require(account == _msgSender(), "only from account");
        uint256 owed = unclaimedPaste[account];
        if (owed != 0) {
            delete unclaimedPaste[account];
            paste.mint(_msgSender(), owed);
            emit claimUnclaimed(account, owed);
        }
    }

    /**
     * @dev calculate the amount of infected human paste to be rewarded to each mansuit staked
     * @param tokenId - id of the mansuit shall be rewarded
     * @return award - the amount of paste shall be awarded to the zombie
     */
    function _calculateInfectionBonus(uint256 tokenId) private view returns (uint256 award) {
        uint80 stakedTime = stakedManSuit[tokenId].value;
        for (uint i = 0; i < pasteShares.length; i++) {
            if (pasteShares[i].infectedTime > stakedTime) award += pasteShares[i].shareAmount;
        }
    }

    /** 
     * @dev invoked when stakedHumanIds is about to change from 0 to 1+ (addHuman() + firstHuman modifier)
     * so as to reset any infection state: total infected & infection power to zero, lastManSuitChanged to current time, 
     * thus, effectively pauses infection when stakedHumanIds = 0; 
     */
    function _resumeInfection () private { // 
        lastManSuitChanged = block.timestamp;
        totalInfected = 0;
        cumInfectionPower = 0;
        emit UpdateInfectionPower(0);
    }

    // before adding a human, check whether it is the first human being added
    // can be when mansuit are zero or more than zero
    modifier _firstHumanCheck() {
        if (stakedHumanIds.length == 0) _resumeInfection(); 
        _;
    }


    /** --- LIMBO --- */
    // limbo allows certain infected human (either from infection or from termination) to make a choice
    /**
     * @dev move to limbo with token value being set to zero
     * mansuit is moved to limbo in two situation:
     * 1) human with escape is infected during infection()
     * 2) human fails termination and is infected
     */
    function _moveManSuitToLimbo(Stake memory stake) private _updateEarnings {
        limboManSuit[stake.tokenId] = Stake({
            owner: stake.owner,
            tokenId: stake.tokenId,
            value: 0,
            escape: stake.escape
        });
        limboList.push(stake.tokenId);
    }

    /**
     * 1) limbo info is deleted; 2) if unstake, transfer back to owner; if stake, move to area, 
     * which will reset stake value and keep other the same
     */
    function chooseFromLimbo(uint256 tokenId, bool unstake) external {
        Stake memory limbo = limboManSuit[tokenId]; 
        require(limbo.owner == _msgSender(), "only owner");
        
        delete limboManSuit[tokenId];
        _arrayRemoveValue(tokenId, limboList);

        if (unstake) _unstakeFromLimbo(_msgSender(), tokenId); 
        else _restakeFromLimbo(_msgSender(), tokenId);
        
        emit ChooseFromLimbo(tokenId, unstake);
    }

    // choice 1: unstake as mansuit
    function _unstakeFromLimbo(address owner, uint256 tokenId) private {
        manSuit.safeTransferFrom(address(this), owner, tokenId, ""); 
    }

    // choice 2: restake back as mansuit
    function _restakeFromLimbo(address owner, uint256 tokenId) private _updateEarnings {
        _moveManSuitToArea(owner, tokenId);
    }




    /* --- TERMINATE --- **/
    /**
     * 
     */
    function initTermination(uint256 tokenId) external _updateEarnings {
        // 1) require human token belongs to owner and in the human pool.
        Stake memory humanStake = stakedHuman[tokenId]; 
        require(humanStake.owner == _msgSender(), "only owner");
        require(stakedManSuitIds.length != 0, "no mansuit");
        paste.burn(_msgSender(), TERMINATION_COST);
        // 2) pick a pseudo-random mansuit to init terminate
        uint256 manSuitIndex = _randomIndexFromArray(tokenId, stakedManSuitIds);
        uint256 manSuitId = stakedManSuitIds[manSuitIndex]; 
        Stake memory manSuitStake = stakedManSuit[manSuitId];
        // 3) remove them from each's staked, save unclaimed $PASTE, and move them to duels
        _removeHumanFromArea(tokenId);
        unclaimedPaste[humanStake.owner] += _calculateBaseAward(humanStake.value, humanStake.escape);
        _removeManSuitFromArea(manSuitId);
        unclaimedPaste[manSuitStake.owner] +=  _calculateBaseAward(manSuitStake.value, false) + _calculateInfectionBonus(manSuitId);
        duels[tokenId] = Duel({
            humanId: tokenId,
            humanOwner: humanStake.owner,
            escape: humanStake.escape,
            manSuitId: manSuitId,
            manSuitOwner: manSuitStake.owner,
            commitNumber: block.number
        });
        duelList.push(tokenId);
        emit InitTermination(tokenId, manSuitId);
    }

    function completeTermination(uint256 tokenId) external _updateEarnings {
        // 1) require caller to be the owner of tokenId, it is human, and it is in duels within 255 blocks
        Duel memory duel = duels[tokenId];
        require(duel.humanOwner == _msgSender(), "only owner"); // allow anyone to call?
        require(duel.commitNumber + 255 > block.number && duel.commitNumber + 5 < block.number, "too early or late");
        // 2) compute randomness and determine who win
        uint256 randomN = uint256(blockhash(duel.commitNumber + 5));
        bool humanWin = randomN % 10 < 3 ? false : true;
        // 3) delete this duel
        delete duels[tokenId]; 
        _arrayRemoveValue(tokenId, duelList);
        if (humanWin) _humanWin(duel);
        else _manSuitWin(duel);
        
        emit CompleteTermination(tokenId, duel.manSuitId, humanWin);
    }

    function defaultTermination(uint256 tokenId) external  _updateEarnings{
        // 1) anyone can call it as long as there is a duel, and duel has past 255 blocks
        Duel memory duel = duels[tokenId];
        require(duel.commitNumber + 255 <= block.number, "wait human");
        // let mansuit win
        delete duels[tokenId]; 
        _arrayRemoveValue(tokenId, duelList);
        _manSuitWin(duel);

        emit CompleteTermination(tokenId, duel.manSuitId, false);
    }

    /**
     * @dev when human wins, two transformation on uri:
     * 1) mansuit reduced to meatpie; 2) human adds kill count
     * & one state change occur in Area, besides deleting the duel info: 
     * 1) human moves to staked area
     * & one erc721 safe transfer: transfer meatpie back to its owner
     */
    function _humanWin(Duel memory duel) private {
        manSuit.madeToPie(duel.manSuitId); // change mansuit uri to meatpie
        manSuit.addKillCount(duel.humanId);
        _moveHumanToArea(duel.humanOwner, duel.humanId, duel.escape); // move human to stake area
        manSuit.safeTransferFrom(address(this), duel.manSuitOwner, duel.manSuitId, "");// transfer manSuit back to original owner? or let him claim from limbo??
    }

    /**
     * @dev when mansuit wins, human transforms to mansuit 
     * & three state changes occur in Area, besides deleting the duel info:
     * 1) infected human (now mansuit) moves to limbo; 
     * 2) winning mansuit moves to staked area; 
     * 3) save infection PASTE for mansuit owner
     */
    function _manSuitWin(Duel memory duel) private {
        manSuit.transformToManSuit(duel.humanId); // change human uri to mansuit 
        _moveManSuitToLimbo(Stake({ // move the infected to limbo
            owner: duel.humanOwner,
            tokenId: uint8(duel.humanId),
            value: 0,
            escape: duel.escape
        }));
        _moveManSuitToArea(duel.manSuitOwner, duel.manSuitId); // move back mansuit to stake area
        unclaimedPaste[duel.manSuitOwner] += PASTE_PER_HUMAN; // add unclaimed paste to mansuit owner
    }


    /** --- TOOLS --- */ 
    function random(uint256 seed) public view returns (uint256) {
        return uint256(keccak256(abi.encodePacked(
            tx.origin,
            blockhash(block.number - 1),
            block.timestamp,
            seed
        )));
    }

    /** 
     * draw a random index from an array of Ids, i.e., stakedHumanIds or stakedZombieIds
     * @param seed - an id number passed in to generate a random number
     * @param _idArray - reference to a storage array 
     * @return index - a randomly drawn index from the array
     */
    function _randomIndexFromArray(uint256 seed, uint256[] storage _idArray) private view returns (uint256 index) { // change it to internal
        index = (random(seed) & 0xFFFFFFFF) % _idArray.length; // choose a value from 0 to amount of human staked
        index = 0; // ---******** delete it!!!!!! ****** ------
        return index;
    }

    /**
     * remove an array element by index without preserving order
     * basically, move the last element to the deleted spot and remove the last element.
     */
    function _arrayRemoveIndex(uint index, uint256[] storage _idArray) private {
        require(index < _idArray.length);
        _idArray[index] = _idArray[_idArray.length-1];
        _idArray.pop();
    }

    // remove an array element by value, which is token id
    function _arrayRemoveValue(uint value, uint256[] storage _idArray) private {
        for (uint i = 0; i < _idArray.length; i++) {
            if (_idArray[i] == value) {
                _arrayRemoveIndex(i, _idArray);
                return;
            }
        }
        revert("no id");
    }

    function _getIndexFromValue(uint value, uint256[] storage _idArray) private view returns (uint) {
        for (uint i = 0; i < _idArray.length; i++) {
            if (_idArray[i] == value) {
                return i;
            }
        }
        revert("no id");
    }

    function getStakedHumanIds() external view returns(uint256[] memory) {
        return stakedHumanIds;
    }

    function getStakedManSuitIds() external view returns(uint256[] memory) {
        return stakedManSuitIds;
    }

    function getLimboIds() external view returns(uint256[] memory) {
        return limboList;
    }

    function getDuelIds() external view returns(uint256[] memory) {
        return duelList;
    }

    function getPasteShares() external view returns(PasteShare[] memory) {
        return pasteShares;
    }

        
    /*
     * checks if a token is a human alive
     * @param tokenId the ID of the token to check
     * @return sheep - whether or not a token is a Sheep
     */
    function isHuman(uint256 tokenId) internal view returns (bool human) {
        ( , uint16 status, , ) = manSuit.tokenTraits(tokenId);
        human = status == 0 ? true : false;
    }

    function isManSuit(uint256 tokenId) internal view returns (bool ms) {
        ( , uint16 status, , ) = manSuit.tokenTraits(tokenId);
        ms = status == 1 ? true : false;
    }


    function onERC721Received(
        address,
        address from,
        uint256,
        bytes calldata
    ) external pure override returns (bytes4) {
      require(from == address(0x0), "Cannot send tokens");
      return IERC721Receiver.onERC721Received.selector;
    }




}