import {createWorkerClient} from '../../sdk/web/dist/worker-client.js';
import type {AssistOptions,EventInfo,PlayerTimeline,TrainingOptions} from '../../sdk/web/dist/index.js';
import {initializeLegacy} from './legacy.js';

const client=createWorkerClient();
const api=client.engine;
const select=(id:string)=>document.getElementById(id) as HTMLSelectElement;
const input=(id:string)=>document.getElementById(id) as HTMLInputElement;
const element=(id:string)=>document.getElementById(id)!;
const button=(id:string)=>document.getElementById(id) as HTMLButtonElement;
const algorithm=()=>document.getElementById('event-algorithm') as HTMLTextAreaElement;
const assistAlgorithm=()=>document.getElementById('assist-algorithm') as HTMLTextAreaElement;
const eventNames:Record<string,string>={
  '222':'二阶','333':'三阶','444':'四阶','555':'五阶','666':'六阶','777':'七阶',
  '333bld':'三阶盲拧','333fm':'三阶最少步','333oh':'三阶单手','444bld':'四阶盲拧',
  '555bld':'五阶盲拧','333mbld':'三阶多盲',clock:'Clock',minx:'五魔方',pyram:'金字塔',skewb:'斜转',sq1:'Square-1',fto:'FTO',
};
const methodNames:Record<string,string>={cross:'Cross 十字',xcross:'XCross 十字与一组 F2L',eoline:'EOline',eofc:'EOFC',
  'roux-s1':'Roux 第一块','roux-s2':'Roux 分阶段','petrus-s1':'Petrus 第一块','petrus-s2':'Petrus 分阶段',
  'cfop-f2l':'CFOP F2L 分阶段','zz-f2l':'ZZ F2L 分阶段','block-222':'2×2×2 块','eo-dr':'EO / DR 分阶段',
  '333-two-phase':'三阶两阶段完整求解','333-general':'三阶自定义目标','222-face':'二阶一面','222-layer':'二阶一层',
  'sq1-shape-ftm':'Square-1 形状 FTM','sq1-shape-twist':'Square-1 形状 Twist','pyraminx-v':'金字塔 V','skewb-face':'斜转一面'};
const examples:Record<string,string>={pyram:"R U l b'",skewb:'R U B',minx:'R++ D-- U',sq1:'(1,0) / (0,3) /',clock:'UR3+ y2 U2-',fto:'U R BL BR'};
const stagedMethods=new Set(['roux-s2','petrus-s2','cfop-f2l','zz-f2l','eo-dr']);
let events:EventInfo[]=[];
let catalog:Record<string,Record<string,unknown>>={};
let methods:[string,string][]=[];
let isReady=false;
let isRunning=false;
let preview:{event:string;algorithm:string;timeline:PlayerTimeline}|undefined;
let previewRevision=0;
let isPlaying=false;
let playbackRevision=0;
let pendingSeek:number|undefined;
let isDrawing=false;

function example(event:string):string {return examples[event]??"R U R' U'";}
function option(value:string,label:string):HTMLOptionElement {return new Option(label,value);}
function integer(id:string,min=0,max=0xffffffff):number {
  const value=input(id).valueAsNumber;
  if(!Number.isInteger(value)||value<min||value>max)throw new Error(`${(document.querySelector(`label[for="${id}"]`)?.textContent??id)}须为 ${min}–${max} 的整数`);
  return value;
}
function clearOutput(id:string):void {element(id).replaceChildren();}
function outputText(id:string,message:string):void {const paragraph=document.createElement('p');paragraph.textContent=message;element(id).append(paragraph);}
function outputAlgorithm(id:string,formula:string):void {const code=document.createElement('pre');code.textContent=formula||'（空公式）';element(id).append(code);}
function pause():void {playbackRevision++;isPlaying=false;button('play').textContent='播放';}
async function run(label:string,action:()=>Promise<void>):Promise<void> {
  if(isRunning)return;
  isRunning=true;pause();element('workbench-error').textContent='';element('workbench-status').textContent=label;
  document.querySelectorAll('section fieldset').forEach(fieldset=>(fieldset as HTMLFieldSetElement).disabled=true);
  try {await action();element('workbench-status').textContent='已完成';}
  catch(failure){element('workbench-error').textContent=failure instanceof Error?failure.message:String(failure);element('workbench-status').textContent='操作未完成';}
  finally {isRunning=false;document.querySelectorAll('section fieldset').forEach(fieldset=>(fieldset as HTMLFieldSetElement).disabled=!isReady);}
}
function updateEventSupport():void {
  const selected=events.find(event=>event.id===select('event').value);
  button('event-solve').disabled=!selected?.full_solver;
  element('solver-support').textContent=selected?.full_solver?'支持求解；结果会追加到当前公式并回放。':'该项目提供打乱、状态与渲染，暂不提供完整求解。';
  element('blind-count-field').hidden=selected?.id!=='333mbld';
}
function previewPosition(position:number,timeline:PlayerTimeline):{completed:number;progress:number} {
  let remaining=position/1000*timeline.totalDurationMs;
  let completed=0;
  while(completed<timeline.steps.length&&remaining>=timeline.steps[completed].durationMs){remaining-=timeline.steps[completed].durationMs;completed++;}
  return {completed,progress:completed<timeline.steps.length?remaining/timeline.steps[completed].durationMs:0};
}
async function drawAt(position:number):Promise<void> {
  const active=preview,revision=previewRevision;
  if(!active)return;
  const {completed,progress}=previewPosition(position,active.timeline);
  const svg=await api.playerSvg(active.event,active.algorithm,completed,progress);
  if(revision!==previewRevision)return;
  element('player-frame').innerHTML=svg;
  element('event-status').textContent=`${completed}/${active.timeline.steps.length}`;
  element('move-label').textContent=`${Math.round(position/10)}%${active.timeline.steps[completed]?` · ${active.timeline.steps[completed].notation}`:' · 完成'}`;
}
async function requestSeek(position:number):Promise<void> {
  pendingSeek=position;
  if(isDrawing)return;
  isDrawing=true;
  try {while(pendingSeek!==undefined){const next=pendingSeek;pendingSeek=undefined;await drawAt(next);}}
  catch(failure){pause();element('workbench-error').textContent=String(failure);}
  finally {isDrawing=false;}
}
async function showPreview(event:string,formula:string,source:string):Promise<void> {
  pause();pendingSeek=undefined;previewRevision++;
  const snapshot=await api.evaluateEvent(event,formula);
  const timeline=await api.playerTimeline(event,formula);
  preview={event,algorithm:formula,timeline};
  element('preview-source').textContent=`${source} · ${snapshot.solved?'已还原':'未还原'} · ${timeline.steps.length} 步`;
  element('event-net').innerHTML=snapshot.svg;
  const net=element('event-net').querySelector('svg');
  if(net&&!net.hasAttribute('viewBox')){
    const width=parseFloat(net.getAttribute('width')??''),height=parseFloat(net.getAttribute('height')??'');
    if(width>0&&height>0)net.setAttribute('viewBox',`0 0 ${width} ${height}`);
  }
  element('event-state').textContent=JSON.stringify(snapshot.state,null,2);
  input('seek').value='0';
  button('play').disabled=timeline.steps.length===0;
  await drawAt(0);
}
function trainingTypes():[string,Record<string,unknown>][] {return Object.entries(catalog).filter(([,type])=>type.kind!=='official');}
function populateTrainingTypes():void {
  const filter=select('training-event').value;
  select('training-type').replaceChildren();
  const groups=new Map<string,HTMLOptGroupElement>();
  for(const [id,type]of trainingTypes()){
    if(filter&&type.baseEventId!==filter)continue;
    const groupId=String(type.categoryId);
    if(!groups.has(groupId)){const group=document.createElement('optgroup');group.label=`${eventNames[String(type.baseEventId)]} · ${groupId}`;groups.set(groupId,group);select('training-type').append(group);}
    groups.get(groupId)!.append(option(id,id));
  }
}
async function loadTrainingCases():Promise<void> {
  const id=select('training-type').value;
  const cases=await api.trainingCases(id);
  select('training-cases').replaceChildren(...cases.map(trainingCase=>option(trainingCase.id,`${trainingCase.id} · 权重 ${trainingCase.natural_weight}`)));
  select('training-cases').disabled=cases.length===0;
  input('natural').disabled=cases.length===0;
  button('training-clear-cases').disabled=cases.length===0;
  element('case-status').textContent=cases.length?`${cases.length} 个案例；不选则使用全部案例。按住 Ctrl / ⌘ 可多选。`:'该类型直接生成约束状态或子群打乱，无需选择案例。';
  const supportsOrientation=Boolean(catalog[id].orientationTarget);
  element('bottom-field').hidden=!supportsOrientation;
  element('front-field').hidden=!supportsOrientation;
  select('front-color').disabled=!select('bottom-color').value;
  clearOutput('training-output');
}
function trainingOptions():TrainingOptions {
  const options:TrainingOptions={};
  const selected=[...select('training-cases').selectedOptions].map(trainingCase=>trainingCase.value);
  if(selected.length)options.enabled_case_ids=selected;
  if(!input('natural').disabled)options.natural=input('natural').checked;
  if(catalog[select('training-type').value].orientationTarget&&select('bottom-color').value){
    options.orientation={bottomColor:select('bottom-color').value};
    if(select('front-color').value)options.orientation.frontColor=select('front-color').value;
  }
  return options;
}
function currentAssist():[string,string] {return methods.find(([,method])=>method===select('assist-method').value)!;}
function updateAssist():void {
  const [event,method]=currentAssist();
  assistAlgorithm().value=event==='333'||event==='222'?'R U F':example(event);
  element('solutions-field').hidden=!method.startsWith('222-');
  input('assist-targets').value='';clearOutput('assist-output');
  element('assist-hint').textContent=`项目：${eventNames[event]}（${event}）。${stagedMethods.has(method)?'分阶段结果须按顺序执行；每行预览包含此前步骤。':'每行展示一个目标的求解结果，可查看相应状态。'}`;
}
function showAssistResults(event:string,formula:string,method:string,solutions:Awaited<ReturnType<typeof api.solveAssist>>[number]['solutions']):void {
  const wrapper=document.createElement('div');wrapper.className='table-scroll';
  const table=document.createElement('table');
  const header=table.createTHead().insertRow();
  for(const label of ['目标','观察转体','还原公式','深度 / FTM / QTM','预览']){const cell=document.createElement('th');cell.textContent=label;header.append(cell);}
  const body=table.createTBody();let prior='';
  for(const solution of solutions){
    const row=body.insertRow();
    const composed=`${formula} ${stagedMethods.has(method)?prior:''} ${solution.setupRotation} ${solution.solution}`.trim();
    if(stagedMethods.has(method))prior+=` ${solution.setupRotation} ${solution.solution}`;
    for(const text of [solution.targetLabel,solution.setupRotation||'—',solution.solution||'（无需转动）',`${solution.depth} / ${solution.metric.ftm} / ${solution.metric.qtm}`]){const cell=row.insertCell();const code=document.createElement('code');code.textContent=text;cell.append(code);}
    const view=document.createElement('button');view.textContent='预览结果';view.className='secondary';view.addEventListener('click',()=>void run('正在预览辅助解…',async()=>{await showPreview(event,composed,`${method} · ${solution.targetLabel}`);element('preview').scrollIntoView({block:'start'});}));row.insertCell().append(view);
  }
  wrapper.append(table);element('assist-output').append(wrapper);
}

select('event').addEventListener('change',()=>void run('正在切换项目…',async()=>{algorithm().value=example(select('event').value);clearOutput('event-output');updateEventSupport();await showPreview(select('event').value,algorithm().value,eventNames[select('event').value]);}));
button('event-apply').addEventListener('click',()=>void run('正在渲染…',()=>showPreview(select('event').value,algorithm().value,eventNames[select('event').value])));
button('event-generate').addEventListener('click',()=>void run('正在生成项目打乱…',async()=>{
  const event=select('event').value,seed=integer('event-seed');clearOutput('event-output');
  const generated=event==='333mbld'?await api.generateMultiBlind(seed,integer('blind-count',2,100)):[await api.generateEvent(event,seed)];
  for(const [index,scramble]of generated.entries()){
    if(generated.length>1)outputText('event-output',`第 ${index+1} 个魔方`);
    outputAlgorithm('event-output',scramble.algorithm);
    if(generated.length>1){const view=document.createElement('button');view.className='secondary';view.textContent=`查看第 ${index+1} 个`;view.addEventListener('click',()=>void run('正在渲染…',async()=>{algorithm().value=scramble.algorithm;await showPreview(event,scramble.algorithm,`三阶多盲 · 第 ${index+1} 个`);}));element('event-output').append(view);}
  }
  algorithm().value=generated[0].algorithm;
  await showPreview(event,algorithm().value,`${eventNames[event]} · 种子 ${seed}${generated.length>1?' · 第 1 个':''}`);
}));
button('event-inverse').addEventListener('click',()=>void run('正在计算逆公式…',async()=>{const inverse=await api.inverseEvent(select('event').value,algorithm().value);clearOutput('event-output');outputText('event-output','逆公式');outputAlgorithm('event-output',inverse);}));
button('event-solve').addEventListener('click',()=>void run('正在求解…',async()=>{
  const event=select('event').value,solution=await api.solveEvent(event,algorithm().value);
  clearOutput('event-output');outputText('event-output','还原公式');outputAlgorithm('event-output',solution);
  algorithm().value=`${algorithm().value} ${solution}`.trim();await showPreview(event,algorithm().value,`${eventNames[event]} · 求解回放`);
}));
select('bottom-color').addEventListener('change',()=>{select('front-color').disabled=!select('bottom-color').value;});
select('training-event').addEventListener('change',()=>void run('正在载入训练类型…',async()=>{populateTrainingTypes();await loadTrainingCases();}));
select('training-type').addEventListener('change',()=>void run('正在载入案例…',loadTrainingCases));
button('training-clear-cases').addEventListener('click',()=>{for(const trainingCase of select('training-cases').options)trainingCase.selected=false;});
button('training-generate').addEventListener('click',()=>void run('正在生成训练打乱…',async()=>{
  const id=select('training-type').value,scramble=await api.generateTraining(id,integer('training-seed'),trainingOptions());
  clearOutput('training-output');outputText('training-output',`${id} · 种子 ${scramble.seed}${scramble.case_id?` · 案例 ${scramble.case_id}`:''}`);
  outputAlgorithm('training-output',scramble.algorithm);
  if(scramble.orientation)outputText('training-output',`朝向：底面 ${scramble.orientation.bottomColor} / 正面 ${scramble.orientation.frontColor}`);
  outputText('training-output','下方图与动画已更新。');
  await showPreview(scramble.event_id,scramble.algorithm,`训练 ${id}${scramble.case_id?` · ${scramble.case_id}`:''}`);
}));
select('assist-method').addEventListener('change',updateAssist);
button('assist-run').addEventListener('click',()=>void run('正在运行辅助求解…',async()=>{
  const [event,method]=currentAssist(),formula=assistAlgorithm().value,options:AssistOptions={};
  if(input('assist-depth').value)options.max_depth=integer('assist-depth',0,30);
  if(input('assist-targets').value.trim())options.targets=input('assist-targets').value.split(/[,，]/).map(target=>target.trim()).filter(Boolean);
  if(method.startsWith('222-'))options.max_solutions_per_target=integer('assist-count',1,64);
  clearOutput('assist-output');
  const results=await api.solveAssist(event,[method],formula,options);
  for(const result of results){outputText('assist-output',`${methodNames[method]} · ${result.solutions.length} 条结果`);showAssistResults(event,formula,method,result.solutions);}
}));
input('seek').addEventListener('input',()=>{pause();void requestSeek(Number(input('seek').value));});
button('restart').addEventListener('click',()=>{pause();input('seek').value='0';void requestSeek(0);});
button('play').addEventListener('click',()=>{
  if(isPlaying){pause();return;}if(!preview?.timeline.totalDurationMs)return;
  if(Number(input('seek').value)>=1000)input('seek').value='0';
  isPlaying=true;button('play').textContent='暂停';const revision=++playbackRevision;let previous=performance.now();
  function tick(now:number){if(!isPlaying||revision!==playbackRevision||!preview)return;const position=Math.min(1000,Number(input('seek').value)+(now-previous)*Number(select('speed').value)/preview.timeline.totalDurationMs*1000);previous=now;input('seek').value=String(position);void requestSeek(position);if(position>=1000)pause();else requestAnimationFrame(tick);}
  requestAnimationFrame(tick);
});
window.addEventListener('pagehide',()=>{pause();client.dispose();});
initializeLegacy(api);
void run('正在载入能力目录…',async()=>{
  [events,catalog,methods]=await Promise.all([api.eventCatalog(),api.typeCatalog(),api.assistMethods()]);
  select('event').replaceChildren(...events.map(event=>option(event.id,`${eventNames[event.id]} · ${event.id}`)));select('event').value='333';updateEventSupport();
  for(const event of [...new Set(trainingTypes().map(([,type])=>String(type.baseEventId)))])select('training-event').append(option(event,`${eventNames[event]} · ${event}`));
  populateTrainingTypes();select('training-type').value='333.pll';await loadTrainingCases();
  const groups=new Map<string,HTMLOptGroupElement>();
  for(const [event,method]of methods){if(!groups.has(event)){const group=document.createElement('optgroup');group.label=`${eventNames[event]} · ${event}`;groups.set(event,group);select('assist-method').append(group);}groups.get(event)!.append(option(method,`${methodNames[method]??method} · ${method}`));}
  updateAssist();
  await showPreview('333',algorithm().value,'三阶示例');
  element('catalog-status').textContent=`${events.length} 类标准项目 · ${trainingTypes().length} 类训练打乱 · ${methods.length} 种辅助求解`;
  isReady=true;
});
