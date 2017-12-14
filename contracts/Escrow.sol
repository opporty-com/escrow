pragma solidity ^0.4.15;

import "./OpportyToken.sol";
import "./Ownable.sol";


contract Escrow is Ownable {
  // status of the project
  enum Status { NEW, PAYED, WORKDONE, CLAIMED, CLOSED }

  // status of the current work
  enum WorkStatus {NEW, STARTED, FULLYDONE, PARTIALLYDONE }

  // token address
  address tokenHolder = 0x08990456DC3020C93593DF3CaE79E27935dd69b9;

  // execute funciton only by token holders
  modifier onlyShareholders {
      require (token.balanceOf(msg.sender) > 0);
      _;
  }

  // transaction only after deadline
  modifier afterDeadline(uint idProject)
  {
    Project memory project = projects[idProject];
    require (now > project.deadline) ;
    _;
  }

  // transaction can be executed  by project client
  modifier onlyClient(uint idProject) {
    Project memory project = projects[idProject];

    require (project.client == msg.sender);
    _;
  }

  // transaction can be executed only by performer
  modifier onlyPerformer(uint idProject) {
    Project memory project = projects[idProject];
    require (project.performer == msg.sender);
    _;
  }

  // project in Opporty system
  // TODO: decrease size of struct
  struct Project {
    uint id;
    string  name;
    address client;
    address performer;
    uint deadline;
    uint sum;
    Status status;
    string report;
    WorkStatus wstatus;
    uint votingDeadline;
    uint numberOfVotes;
    uint totalVotesNeeded;
    bool withdrawed;
    Vote[] votes;
    mapping (address => bool) voted;
  }
  // one vote - one element of struct
  struct Vote {
      bool inSupport;
      address voter;
  }
  // event - project was added
  event ProjectAdded(uint projectID, address performer,  string name,uint sum );
  // event - fund was transferred
  event FundTransfered(address recipient, uint amount);
  // work was done
  event WorkDone(uint projectId, address performer, WorkStatus status, string link);
  // already voted
  event Voted(uint projectID, bool position, address voter);
  // status of project changed
  event ChangedProjectStatus(uint projectID, Status status);

  event log(string val);
  event loga(address addr);
  event logi(uint i);

  // token for payments
  OpportyToken token;

  // all projects
  Project[] projects;


  // number or projects
  uint public numProjects;

  function Escrow(address tokenUsed)
  {
    token = OpportyToken(tokenUsed);
  }

  function getNumberOfProjects() constant  returns(uint)
  {
    return numProjects;
  }

  // Add a project to blockchain
  // idExternal - id in opporty
  // name 
  // performer 
  // duration
  // sum 
  function addProject(uint idExternal, string name, address performer, uint durationInMinutes, uint sum)
     returns (uint projectId)
  {
    projectId = projects.length++;
    Project storage p = projects[projectId];
    p.id = idExternal;
    p.name = name;
    p.client = msg.sender;
    p.performer = performer;
    p.deadline = now + durationInMinutes * 1 minutes;
    p.sum = sum * 1 ether;
    p.status = Status.NEW;

    ProjectAdded(projectId, performer, name, sum);
    return projectId;
  }

  function getProjectReport(uint idProject) constant returns (string t) {
    Project memory p = projects[idProject];
    return p.report;
  }

  function getJudgeVoted(uint idProject, address judge) constant returns (bool voted) {
    Project memory p = projects[idProject];
    if (p.voted[judge]) 
      return true;
       else 
      return false;
  }

  // get status of project 
  function getStatus(uint idProject) constant returns (uint t) {
    Project memory p = projects[idProject];
    return uint(p.status);
  } 

  // is deadline 
  function isDeadline(uint idProject) constant returns (bool f) {
      Project memory p = projects[idProject];

      if (now >= p.deadline) {
        return true;
      } else {
        return false;
      }
  }
  // pay for project by client
  function payFor(uint idProject) payable onlyClient(idProject) returns (bool) {
    Project storage project = projects[idProject];

    uint price = project.sum;

    require (project.status == Status.NEW);
    if (msg.value >= price) {
      project.status = Status.PAYED;
      FundTransfered(this, msg.value);
      ChangedProjectStatus(idProject, Status.PAYED);
      return true;
    } else {
      revert();
    }
  }
  // pay by project in tokens
  function payByTokens(uint idProject) onlyClient(idProject) onlyShareholders {
    Project storage project = projects[idProject];
    require (project.sum <= token.balanceOf(project.client));
    require (token.transferFrom(project.client, tokenHolder, project.sum));

    ChangedProjectStatus(idProject, Status.PAYED);
  }
  // change status of project - done
  // and provide report
  function workDone(uint idProject, string report, WorkStatus status) onlyPerformer(idProject) afterDeadline(idProject) {
    Project storage project = projects[idProject];
    require (project.status == Status.PAYED);

    project.status = Status.WORKDONE;
    project.report = report;
    project.wstatus = status;

    WorkDone(idProject, project.performer, project.wstatus, project.report);
    ChangedProjectStatus(idProject, Status.WORKDONE);
  }
  // work is done - execured by client
  function acceptWork(uint idProject) onlyClient(idProject) afterDeadline(idProject) {
    Project storage project = projects[idProject];
    require (project.status == Status.WORKDONE);
    project.status = Status.CLOSED;
    ChangedProjectStatus(idProject, Status.CLOSED);
  }
  // claim - project was undone (?)
  // numberOfVoters 
  // debatePeriod - time for voting
  function claimWork(uint idProject, uint numberOfVoters, uint debatePeriod) afterDeadline(idProject) {
    Project storage project = projects[idProject];
    require (project.status == Status.WORKDONE);
    project.status = Status.CLAIMED;
    project.votingDeadline = now + debatePeriod * 1 minutes;
    project.totalVotesNeeded = numberOfVoters;
    ChangedProjectStatus(idProject, Status.CLAIMED);
  }

  // voting process
  function vote(uint idProject, bool supportsProject)
        returns (uint voteID)
  {
        Project storage p = projects[idProject];
        require(p.voted[msg.sender] != true);
        require(p.status == Status.CLAIMED);
        require(p.numberOfVotes < p.totalVotesNeeded);
        require(now >= p.votingDeadline );

        voteID = p.votes.length++;
        p.votes[voteID] = Vote({inSupport: supportsProject, voter: msg.sender});
        p.voted[msg.sender] = true;
        p.numberOfVotes = voteID + 1;
        Voted(idProject,  supportsProject, msg.sender);
        return voteID;
  }

  // safeWithdrawal - get money by performer / return money for client
  function safeWithdrawal(uint idProject) afterDeadline(idProject)
  {
      Project storage p = projects[idProject];

      // if status closed and was not withdrawed
      require(p.status == Status.CLAIMED || p.status == Status.CLOSED && !p.withdrawed);

      // if project closed
      if (p.status == Status.CLOSED) {
        
        if (msg.sender == p.performer && !p.withdrawed && msg.sender.send(p.sum) ) {
          FundTransfered(msg.sender, p.sum);
          p.withdrawed = true;
        } else {
          revert();
        }
      } else {
        // claim
        uint yea = 0;
        uint nay = 0;
        // calculating votes
        for (uint i = 0; i <  p.votes.length; ++i) {
            Vote storage v = p.votes[i];

            if (v.inSupport) {
                yea += 1;
            } else {
                nay += 1;
            }
        }
        // если уже время голосования закончилось
        if (now >= p.votingDeadline) {
         if (msg.sender == p.performer && p.numberOfVotes >= p.totalVotesNeeded ) {
            if (yea>nay && !p.withdrawed && msg.sender.send(p.sum)) {
              FundTransfered(msg.sender, p.sum);
              p.withdrawed = true;
              p.status = Status.CLOSED;
              ChangedProjectStatus(idProject, Status.CLOSED);
            }
          }
    
          if (msg.sender == p.client) {
            if (nay>=yea && !p.withdrawed &&  msg.sender.send(p.sum)) {
              FundTransfered(msg.sender, p.sum);
              p.withdrawed = true;
              p.status = Status.CLOSED;
              // меняем статус проекта
              ChangedProjectStatus(idProject, Status.CLOSED);
            }
          }
        } else {
          revert();
        }
      }
  }

  // get tokens  
  function safeWithdrawalTokens(uint idProject) afterDeadline(idProject)
  {
    Project storage p = projects[idProject];
    require(p.status == Status.CLAIMED || p.status == Status.CLOSED && !p.withdrawed);

    if (p.status == Status.CLOSED) {

      if (msg.sender == p.performer && token.transfer(p.performer, p.sum) && !p.withdrawed) {
        FundTransfered(msg.sender, p.sum);
        p.withdrawed = true;
      } else {
        revert();
      }
    }
  }
}
