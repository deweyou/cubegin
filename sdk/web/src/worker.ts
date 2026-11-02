import {createCubegin} from './index.js';
const engine=createCubegin();
self.onmessage=async ({data})=> {
  const {id,method,args}=data;
  try {
    const api=await engine;
    if(!Object.hasOwn(api,method)) throw new Error('unknown operation');
    const operation=api[method as keyof typeof api] as (...args:unknown[])=>unknown;
    self.postMessage({id,value:operation(...args)});
  } catch(error) { self.postMessage({id,error:error instanceof Error?error.message:String(error)}); }
};
