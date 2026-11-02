import type {Engine,TrainingOptions,AssistOptions} from './index.js';
export type AsyncEngine = { [K in keyof Engine]:(...args:Parameters<Engine[K]>)=>Promise<ReturnType<Engine[K]>> };
export interface WorkerClient { engine:AsyncEngine; dispose():void }
/** Owns a dedicated Worker. dispose terminates ongoing work and rejects pending calls. */
export function createWorkerClient():WorkerClient {
  const worker=new Worker(new URL('./worker.js',import.meta.url),{type:'module'});
  let nextId=0; let disposed=false;
  const pending=new Map<number,{resolve:(value:unknown)=>void;reject:(error:Error)=>void}>();
  function rejectAll(error:Error) { for(const request of pending.values()) request.reject(error); pending.clear(); }
  worker.onmessage=({data}:{data:{id:number;value?:unknown;error?:string}})=> {
    const request=pending.get(data.id); if(!request) return; pending.delete(data.id);
    if(data.error!==undefined) request.reject(new Error(data.error)); else request.resolve(data.value);
  };
  worker.onerror=event=>{ disposed=true; worker.terminate(); rejectAll(new Error(event.message || 'worker failed')); };
  const invoke=(method:keyof Engine,args:unknown[])=>new Promise((resolve,reject)=> {
    if(disposed) { reject(new Error('worker disposed')); return; }
    const id=nextId++; pending.set(id,{resolve,reject}); worker.postMessage({id,method,args});
  });
  const engine={
    playerTimeline:(event:string,algorithm:string)=>invoke('playerTimeline',[event,algorithm]),
    playerFrame:(event:string,algorithm:string,completed:number,progress:number)=>invoke('playerFrame',[event,algorithm,completed,progress]),
    playerSvg:(event:string,algorithm:string,completed:number,progress:number)=>invoke('playerSvg',[event,algorithm,completed,progress]),
    validateFmc:(scramble:string,solution:string)=>invoke('validateFmc',[scramble,solution]),
    generateBatch:(id:string,seed:number,count:number,options:TrainingOptions={})=>invoke('generateBatch',[id,seed,count,options]),
    typeCatalog:()=>invoke('typeCatalog',[]),
    trainingCases:(id:string)=>invoke('trainingCases',[id]),
    generateTraining:(id:string,seed:number,options:TrainingOptions={})=>invoke('generateTraining',[id,seed,options]),
    assistMethods:()=>invoke('assistMethods',[]),
    solveAssist:(event:string,methods:string[],algorithm:string,options:AssistOptions={})=>invoke('solveAssist',[event,methods,algorithm,options]),
    eventCatalog:()=>invoke('eventCatalog',[]),
    evaluateEvent:(event:string,algorithm:string)=>invoke('evaluateEvent',[event,algorithm]),
    generateEvent:(event:string,seed:number)=>invoke('generateEvent',[event,seed]),
    generateMultiBlind:(seed:number,count:number)=>invoke('generateMultiBlind',[seed,count]),
    inverseEvent:(event:string,algorithm:string)=>invoke('inverseEvent',[event,algorithm]),
    solveEvent:(event:string,algorithm:string)=>invoke('solveEvent',[event,algorithm]),
    timelineEvent:(event:string,algorithm:string)=>invoke('timelineEvent',[event,algorithm]),
    version:()=>invoke('version',[]), evaluate:(algorithm:string)=>invoke('evaluate',[algorithm]),
    inverse:(algorithm:string)=>invoke('inverse',[algorithm]), solve:(facelets:string)=>invoke('solve',[facelets]),
    scramble:(seed:number)=>invoke('scramble',[seed]), render:(facelets:string)=>invoke('render',[facelets]),
    timeline:(algorithm:string)=>invoke('timeline',[algorithm]),
  } as AsyncEngine;
  return {engine,dispose(){disposed=true;worker.terminate();rejectAll(new Error('worker disposed'));}};
}
