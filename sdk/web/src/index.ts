import init, * as wasm from '../wasm/cubegin_wasm.js';
export interface Snapshot { facelets:string; solved:boolean; svg:string }
export interface Scramble { algorithm:string; facelets:string; seed:number }
export interface Step { notation:string; axis:[number,number,number]; angle_radians:number; duration_ms:number; before:string; after:string }
export interface EventInfo {id:string;puzzle:string;full_solver:boolean}
export interface EventSnapshot {event_id:string;state:Record<string,unknown>;solved:boolean;svg:string}
export interface EventScramble {event_id:string;algorithm:string;seed:number;state:Record<string,unknown>}
export interface EventStep {notation:string;before:Record<string,unknown>;after:Record<string,unknown>;duration_ms:number}
export interface Orientation {bottomColor:string;frontColor?:string}
export interface TrainingOptions {enabled_case_ids?:string[];natural?:boolean;orientation?:Orientation}
export interface TrainingScramble extends EventScramble {scramble_type_id:string;case_id:string|null;orientation:Orientation|null}
export interface AssistOptions {targets?:string[];max_depth?:number;max_solutions_per_target?:number}
export interface AssistSolution {method:string;target:string;targetLabel:string;setupRotation:string;solution:string;depth:number;metric:{ftm:number;qtm:number}}
export interface AssistResult {method:string;scramble:string;solutions:AssistSolution[]}
export interface PlayerModel {cameraDistance:number;cameraOrbit?:{yaw:number;pitch:number};pieces:Record<string,unknown>[]}
export interface PlayerTimeline {schemaVersion:number;eventId:string;model:PlayerModel;steps:{notation:string;operations:Record<string,unknown>[];durationMs:number}[];totalDurationMs:number}
export interface FmcValidation {rawSolution:string;normalizedSolution:string|null;moveCount:number|null;executionMoveCount:number|null;status:"valid"|"dnf"|"suspected-inverse";reason:string|null;inverseMatchLength:number}
export interface Engine {
  generateBatch(id:string,seed:number,count:number,options?:TrainingOptions):(EventScramble|TrainingScramble)[];
  validateFmc(scramble:string,solution:string):FmcValidation;
  playerTimeline(event:string,algorithm:string):PlayerTimeline;
  playerFrame(event:string,algorithm:string,completed:number,progress:number):PlayerModel;
  playerSvg(event:string,algorithm:string,completed:number,progress:number):string;
  typeCatalog():Record<string,Record<string,unknown>>;
  trainingCases(id:string):{id:string;natural_weight:number}[];
  generateTraining(id:string,seed:number,options?:TrainingOptions):TrainingScramble;
  assistMethods():[string,string][];
  solveAssist(event:string,methods:string[],algorithm:string,options?:AssistOptions):AssistResult[];
  eventCatalog():EventInfo[];
  evaluateEvent(event:string,algorithm:string):EventSnapshot;
  generateEvent(event:string,seed:number):EventScramble;
  generateMultiBlind(seed:number,count:number):EventScramble[];
  inverseEvent(event:string,algorithm:string):string;
  solveEvent(event:string,algorithm:string):string;
  timelineEvent(event:string,algorithm:string):EventStep[];
  version():string;
  evaluate(algorithm:string):Snapshot;
  inverse(algorithm:string):string;
  solve(facelets:string):string;
  scramble(seed:number):Scramble;
  render(facelets:string):string;
  timeline(algorithm:string):Step[];
}
function call<T>(operation:()=>T):T {
  try { return operation(); } catch (error) { throw error instanceof Error ? error : new Error(String(error)); }
}
/** Loads once per JS realm. Solver calls are synchronous; use the worker client in interactive apps. */
export async function createCubegin(source?:BufferSource | URL | string):Promise<Engine> {
  await init(source === undefined ? undefined : {module_or_path:source});
  return {
    playerTimeline:(event,algorithm)=>call(()=>JSON.parse(wasm.player_timeline(event,algorithm))),
    playerFrame:(event,algorithm,completed,progress)=>call(()=>{u32(completed);return JSON.parse(wasm.player_frame(event,algorithm,completed,progress));}),
    playerSvg:(event,algorithm,completed,progress)=>call(()=>{u32(completed);return wasm.player_svg(event,algorithm,completed,progress);}),
    validateFmc:(scramble,solution)=>JSON.parse(wasm.validate_fmc(scramble,solution)),
    generateBatch:(id,seed,count,options={})=>call(()=>{u32(seed);u32(count);return JSON.parse(wasm.generate_batch(id,seed,count,JSON.stringify(options)));}),
    typeCatalog:()=>call(()=>JSON.parse(wasm.type_catalog())),
    trainingCases:id=>call(()=>JSON.parse(wasm.training_cases(id))),
    generateTraining:(id,seed,options={})=>call(()=>{u32(seed);return JSON.parse(wasm.generate_training(id,seed,JSON.stringify(options)));}),
    assistMethods:()=>call(()=>JSON.parse(wasm.assist_methods())),
    solveAssist:(event,methods,algorithm,options={})=>call(()=>JSON.parse(wasm.solve_assist(event,JSON.stringify(methods),algorithm,JSON.stringify(options)))),
    eventCatalog:()=>call(()=>JSON.parse(wasm.event_catalog()) as EventInfo[]),
    evaluateEvent:(event,algorithm)=>call(()=>JSON.parse(wasm.evaluate_event(event,algorithm)) as EventSnapshot),
    generateEvent:(event,seed)=>call(()=>{u32(seed);return JSON.parse(wasm.generate_event(event,seed)) as EventScramble;}),
    generateMultiBlind:(seed,count)=>call(()=>{u32(seed);u32(count);return JSON.parse(wasm.generate_multi_blind(seed,count)) as EventScramble[];}),
    inverseEvent:(event,algorithm)=>call(()=>wasm.inverse_event(event,algorithm)),
    solveEvent:(event,algorithm)=>call(()=>wasm.solve_event(event,algorithm)),
    timelineEvent:(event,algorithm)=>call(()=>JSON.parse(wasm.timeline_event(event,algorithm)) as EventStep[]),
    version:()=>wasm.version(),
    evaluate:algorithm=>call(()=>JSON.parse(wasm.evaluate(algorithm)) as Snapshot),
    inverse:algorithm=>call(()=>wasm.inverse(algorithm)),
    solve:facelets=>call(()=>wasm.solve(facelets)),
    scramble:seed=>call(()=> {
      if (!Number.isInteger(seed) || seed<0 || seed>0xffffffff) throw new RangeError('seed must be a u32 integer');
      return JSON.parse(wasm.scramble(seed)) as Scramble;
    }),
    render:facelets=>call(()=>wasm.render(facelets)),
    timeline:algorithm=>call(()=>JSON.parse(wasm.timeline(algorithm)) as Step[]),
  };
}

function u32(value:number):void {if(!Number.isInteger(value)||value<0||value>0xffffffff)throw new RangeError("expected a u32 integer");}
